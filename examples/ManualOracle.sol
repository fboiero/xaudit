// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IXscrow.sol";
import "./structures/Request.sol";

contract ManualOracle is Ownable {
    IXscrow private _xscrow;
    mapping(address => uint256) _withdrawRequests;
    mapping(address => uint256) _executionRequests;

    event RequestWithdrawOf(address indexed aPayee, uint256 anAmount);
    event RequestPartialWithdrawOf(address indexed aPayee, uint256 anAmount);
    event RequestExecuteDepositOf(address indexed aPayee, uint256 anAmount);
    event DataFulfilled(address indexed aPayee, bool allowed);
    event XscrowUpdated(address indexed aXscrow);

    error AddressZeroNotAllowed();
    error AlreadyRequested();
    error RequestNotFound();
    error NotXscrow();

    modifier onlyXscrow() {
        if (msg.sender != address(_xscrow)) revert NotXscrow();
        _;
    }

    modifier notRequested(
        mapping(address => uint256) storage requests,
        address aPayee
    ) {
        if (requests[aPayee] != 0) revert AlreadyRequested();
        _;
    }

    modifier alreadyRequested(
        mapping(address => uint256) storage requests,
        address aPayee
    ) {
        if (requests[aPayee] == 0) revert RequestNotFound();
        _;
    }

    function xscrow() external view returns (address) {
        return address(_xscrow);
    }

    function updateXscrow(IXscrow aXscrow) external onlyOwner {
        if (address(aXscrow) == address(0)) revert AddressZeroNotAllowed();
        emit XscrowUpdated(address(aXscrow));
        _xscrow = aXscrow;
    }

    function requestWithdrawOf(
        address aPayee,
        uint256 anAmount
    )
        external
        onlyXscrow
        notRequested(_withdrawRequests, aPayee)
        returns (bytes32)
    {
        _withdrawRequests[aPayee] = anAmount;
        emit RequestWithdrawOf(aPayee, anAmount);
        return _fakeRequestId();
    }

    function requestPartialWithdrawOf(
        address aPayee,
        uint256 anAmount
    )
        external
        onlyXscrow
        notRequested(_withdrawRequests, aPayee)
        returns (bytes32)
    {
        _withdrawRequests[aPayee] = anAmount;
        emit RequestPartialWithdrawOf(aPayee, anAmount);
        return _fakeRequestId();
    }

    function withdrawRequestOf(
        address aPayee
    ) external view onlyOwner returns (uint256) {
        return _withdrawRequests[aPayee];
    }

    function fulfillWithdraw(
        address aPayee,
        bool canWithdraw
    ) external onlyOwner alreadyRequested(_withdrawRequests, aPayee) {
        delete _withdrawRequests[aPayee];
        emit DataFulfilled(aPayee, canWithdraw);
        _xscrow.withdrawOf(aPayee, canWithdraw);
    }

    function fulfillPartialWithdraw(
        address aPayee,
        bool canWithdraw
    ) external onlyOwner alreadyRequested(_withdrawRequests, aPayee) {
        uint256 amount = _withdrawRequests[aPayee];
        delete _withdrawRequests[aPayee];
        emit DataFulfilled(aPayee, canWithdraw);
        _xscrow.partialWithdrawOf(aPayee, amount, canWithdraw);
    }

    function requestExecuteDepositOf(
        address aPayee,
        uint256 anAmount
    )
        external
        onlyXscrow
        notRequested(_executionRequests, aPayee)
        returns (bytes32)
    {
        _executionRequests[aPayee] = anAmount;
        emit RequestExecuteDepositOf(aPayee, anAmount);
        return _fakeRequestId();
    }

    function executionRequestOf(
        address aPayee
    ) external view onlyOwner returns (uint256) {
        return _executionRequests[aPayee];
    }

    function fulfillExecution(
        address aPayee,
        bool canExecute
    ) external onlyOwner alreadyRequested(_executionRequests, aPayee) {
        delete _executionRequests[aPayee];
        emit DataFulfilled(aPayee, canExecute);
        _xscrow.executeDepositOf(aPayee, canExecute);
    }

    function _fakeRequestId() private view returns (bytes32) {
        return keccak256(abi.encodePacked(this, "1"));
    }
}
