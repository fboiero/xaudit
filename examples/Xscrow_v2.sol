// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./interfaces/NewXscrow.sol";
import "./structures/Warranty.sol";
import "./interfaces/Oracle.sol";
import "./structures/IterableMapping.sol";

contract Xscrow is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    using IterableMapping for IterableMapping.AddressToWarranty;

    IERC20Upgradeable private _token;
    address private _lenderTreasury;
    address private _vendorTreasury;
    NewXscrow private _newXscrow;
    Oracle private _oracle;
    string private _identifier;
    uint256 private _depositFee;
    IterableMapping.AddressToWarranty private _warranties;
    uint256 private _minDepositAmount;
    uint256 private _maxDepositAmount;
    bool private _migrated;
    address private _oldXscrow;

    event WithdrawSuccessful(address indexed aPayee, uint256 anAmount);
    event WithdrawNotAllowed(address indexed aPayee, uint256 anAmount);
    event Deposit(
        address indexed aSponsor,
        uint256 anAmount,
        address indexed aPayee
    );
    event DepositExecuted(address indexed aPayee, uint256 balance);
    event DepositExecutionNotAllowed(address indexed aPayee);
    event OracleUpdated(address indexed anOracle);
    event MinimumDepositAmountUpdated(uint256 anAmount);
    event MaximumDepositAmountUpdated(uint256 anAmount);
    event DepositFeeUpdated(uint256 anAmount);
    event TokenBalanceReceived(uint256 anAmount);
    event XscrowMigrated();

    error FeeOutOfBounds();
    error AddressZeroNotAllowed();
    error NotOracle();
    error NonZeroAmount();
    error MaximumDepositAmountExceeded();
    error InsufficientDepositAmount();
    error NotEnoughBalance();
    error NotOldXscrow();

    modifier onlyOracle() {
        if (msg.sender != address(_oracle)) revert NotOracle();
        _;
    }

    modifier nonZeroAddress(address anAddress) {
        if (anAddress == address(0)) revert AddressZeroNotAllowed();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        IERC20Upgradeable anERC20Token_,
        address aLenderTreasury_,
        address aVendorTreasury_,
        string memory anIdentifier_,
        Oracle anOracle_,
        uint256 aMinimumDepositAmount_,
        uint256 aMaximumDepositAmount_
    )
        public
        initializer
        nonZeroAddress(address(anERC20Token_))
        nonZeroAddress(aLenderTreasury_)
        nonZeroAddress(aVendorTreasury_)
        nonZeroAddress(address(anOracle_))
    {
        _token = anERC20Token_;
        _lenderTreasury = aLenderTreasury_;
        _vendorTreasury = aVendorTreasury_;
        _identifier = anIdentifier_;
        _oracle = anOracle_;
        _minDepositAmount = aMinimumDepositAmount_;
        _maxDepositAmount = aMaximumDepositAmount_;
        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function newXscrow() external view returns (address) {
        return address(_newXscrow);
    }

    function tokenAddress() external view returns (address) {
        return address(_token);
    }

    function lenderTreasury() external view returns (address) {
        return _lenderTreasury;
    }

    function vendorTreasury() external view returns (address) {
        return _vendorTreasury;
    }

    function oracle() external view returns (address) {
        return address(_oracle);
    }

    function identifier() external view returns (string memory) {
        return _identifier;
    }

    function depositFee() external view returns (uint256) {
        return _depositFee;
    }

    function balanceOf(address aPayee) external view returns (uint256) {
        return _balanceOf(aPayee);
    }

    function minimumDepositAmount() external view returns (uint256) {
        return _minDepositAmount;
    }

    function maximumDepositAmount() external view returns (uint256) {
        return _maxDepositAmount;
    }

    function warranty(address aPayee) external view returns (Warranty memory) {
        return _warranties.get(aPayee);
    }

    function migrated() external view returns (bool) {
        return _migrated;
    }

    function oldXscrow() external view returns (address) {
        return _oldXscrow;
    }

    function _transferFeeToVendor(uint256 fee) private {
        if (fee > 0) {
            SafeERC20Upgradeable.safeTransfer(
                _token,
                address(_vendorTreasury),
                fee
            );
        }
    }

    function depositWithPermit(
        address anOwner,
        uint256 anAmount,
        uint256 aDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        SafeERC20Upgradeable.safePermit(
            IERC20PermitUpgradeable(address(_token)),
            anOwner,
            address(this),
            anAmount,
            aDeadline,
            v,
            r,
            s
        );
        _depositTo(anOwner, anAmount, anOwner);
    }

    function deposit(uint256 anAmount) external whenNotPaused {
        _depositTo(msg.sender, anAmount, msg.sender);
    }

    function depositTo(
        address aPayee,
        uint256 anAmount
    ) external whenNotPaused {
        _depositTo(aPayee, anAmount, msg.sender);
    }

    function _depositTo(
        address aPayee,
        uint256 anAmount,
        address source
    ) private whenNotPaused {
        uint256 fee = (_depositFee * anAmount) / 100;
        uint256 amountToDeposit = anAmount - fee;
        emit Deposit(msg.sender, amountToDeposit, aPayee);

        _requireNonZeroAmount(amountToDeposit);

        if (_balanceOf(aPayee) + amountToDeposit > _maxDepositAmount)
            revert MaximumDepositAmountExceeded();

        if (_balanceOf(aPayee) + amountToDeposit < _minDepositAmount)
            revert InsufficientDepositAmount();

        _setCreationDate(aPayee);
        _setBalanceTo(aPayee, _balanceOf(aPayee) + amountToDeposit);
        _transferFrom(source, address(this), anAmount);
        _transferFeeToVendor(fee);
    }

    function _setCreationDate(address aPayee) private {
        Warranty memory aWarranty = _warranties.get(aPayee);
        if (aWarranty.amount == 0) {
            aWarranty.created_at = block.timestamp;
            _warranties.set(aPayee, aWarranty);
        }
    }

    function executeDepositOf(
        address aPayee,
        bool canExecute
    ) external whenNotPaused onlyOracle {
        if (canExecute) {
            uint256 balance = _balanceOf(aPayee);
            emit DepositExecuted(aPayee, balance);
            _requireNonZeroAmount(balance);
            _setBalanceTo(aPayee, 0);
            _transfer(_lenderTreasury, balance);
        } else {
            emit DepositExecutionNotAllowed(aPayee);
        }
    }

    function requestWithdraw() external whenNotPaused {
        uint256 balance = _balanceOf(msg.sender);
        _requireNonZeroAmount(balance);
        _oracle.requestWithdrawOf(msg.sender, balance);
    }

    function requestPartialWithdraw(uint256 anAmount) external whenNotPaused {
        _requireNonZeroAmount(_balanceOf(msg.sender));
        if (anAmount > _balanceOf(msg.sender)) revert NotEnoughBalance();
        _oracle.requestPartialWithdrawOf(msg.sender, anAmount);
    }

    function requestExecuteDepositOf(
        address aPayee
    ) external whenNotPaused onlyOwner {
        uint256 balance = _balanceOf(aPayee);
        _requireNonZeroAmount(balance);
        _oracle.requestExecuteDepositOf(aPayee, balance);
    }

    function partialWithdrawOf(
        address aPayee,
        uint256 anAmount,
        bool canWithdraw
    ) public whenNotPaused onlyOracle {
        if (canWithdraw) {
            emit WithdrawSuccessful(aPayee, anAmount);
            _requireNonZeroAmount(anAmount);
            _setBalanceTo(aPayee, (_balanceOf(aPayee) - anAmount));
            _transfer(aPayee, anAmount);
        } else {
            emit WithdrawNotAllowed(aPayee, anAmount);
        }
    }

    function withdrawOf(
        address aPayee,
        bool canWithdraw
    ) public whenNotPaused onlyOracle {
        uint256 balance = _balanceOf(aPayee);
        if (canWithdraw) {
            emit WithdrawSuccessful(aPayee, balance);
            _requireNonZeroAmount(balance);
            _setBalanceTo(aPayee, 0);
            _transfer(aPayee, balance);
        } else {
            emit WithdrawNotAllowed(aPayee, balance);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _setBalanceTo(address aPayee, uint256 anAmount) internal {
        Warranty memory aWarranty = _warranties.get(aPayee);
        if (anAmount > 0) {
            aWarranty.amount = anAmount;
            aWarranty.updated_at = block.timestamp;
            _warranties.set(aPayee, aWarranty);
        } else {
            _warranties.remove(aPayee);
        }
    }

    function _balanceOf(address aPayee) internal view returns (uint256) {
        return _warranties.get(aPayee).amount;
    }

    function _transfer(address to, uint256 anAmount) internal {
        SafeERC20Upgradeable.safeTransfer(_token, to, anAmount);
    }

    function _transferFrom(
        address from,
        address to,
        uint256 anAmount
    ) internal {
        SafeERC20Upgradeable.safeTransferFrom(_token, from, to, anAmount);
    }

    function _requireNonZeroAmount(uint256 anAmount) internal pure {
        if (anAmount == 0) revert NonZeroAmount();
    }

    function updateLenderTreasury(
        address aTreasury
    ) external onlyOwner nonZeroAddress(aTreasury) {
        _lenderTreasury = aTreasury;
    }

    function updateVendorTreasury(
        address aTreasury
    ) external onlyOwner nonZeroAddress(aTreasury) {
        _vendorTreasury = aTreasury;
    }

    function updateNewXscrow(
        NewXscrow aNewXscrow
    ) external onlyOwner nonZeroAddress(address(aNewXscrow)) {
        _newXscrow = aNewXscrow;
    }

    function updateOracle(
        Oracle anOracle
    ) external onlyOwner nonZeroAddress(address(anOracle)) {
        emit OracleUpdated(address(anOracle));
        _oracle = anOracle;
    }

    function updateDepositFee(uint256 aDepositFee_) external onlyOwner {
        if (aDepositFee_ > 100) revert FeeOutOfBounds();
        emit DepositFeeUpdated(aDepositFee_);
        _depositFee = aDepositFee_;
    }

    function updateMinimumDepositAmount(uint256 anAmount_) external onlyOwner {
        emit MinimumDepositAmountUpdated(anAmount_);
        _minDepositAmount = anAmount_;
    }

    function updateMaximumDepositAmount(uint256 anAmount_) external onlyOwner {
        emit MaximumDepositAmountUpdated(anAmount_);
        _maxDepositAmount = anAmount_;
    }

    function updateOldXscrow(
        address aXscrow
    ) external onlyOwner nonZeroAddress(aXscrow) {
        _oldXscrow = aXscrow;
    }

    function migrateAll()
        external
        whenPaused
        onlyOwner
        nonZeroAddress(address(_newXscrow))
    {
        address anAddress;
        _migrated = true;
        _transfer(address(_newXscrow), _token.balanceOf(address(this)));
        for (uint i = 0; i < _warranties.size(); i++) {
            anAddress = _warranties.getKeyAtIndex(i);
            _newXscrow.restore(_warranties.get(anAddress), anAddress);
        }
        emit XscrowMigrated();
    }

    function migrate() external {
        Warranty memory aWarranty = _warranties.get(msg.sender);
        _warranties.remove(msg.sender);
        _transfer(address(_newXscrow), aWarranty.amount);
        _newXscrow.restore(aWarranty, msg.sender);
    }

    function restore(Warranty memory aWarranty, address aPayee) public {
        if (msg.sender != _oldXscrow) revert NotOldXscrow();
        _requireNonZeroAmount(aWarranty.amount);
        aWarranty.amount += _warranties.get(aPayee).amount;
        _warranties.set(aPayee, aWarranty);
    }

    receive() external payable {
        emit TokenBalanceReceived(msg.value);
    }

    fallback() external payable {
        revert();
    }
}
