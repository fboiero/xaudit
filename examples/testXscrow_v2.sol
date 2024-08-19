// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../contracts/Xscrow.sol";
import "../contracts/fakes/FakeToken.sol";
import "../contracts/fakes/FakeNewXscrow.sol";
import "../contracts/CreditOracle.sol";
import "../contracts/fakes/FakeOperator.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../contracts/fakes/LinkToken.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../contracts/helpers/SigUtils.sol";

import "../contracts/fakes/FakeXscrow.sol";

contract DummyWallet {
    Xscrow private _xscrow;

    constructor(Xscrow xscrow) {
        _xscrow = xscrow;
    }

    function send(uint256 anAmount) external returns (bool) {
        (bool sent, ) = address(_xscrow).call{value: anAmount}("");
        return sent;
    }
}

contract XscrowTest is Test {
    using ECDSA for bytes32;
    SigUtils internal sigUtils;

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

    Xscrow xscrow;
    CreditOracle oracle;
    FakeOperator operator;
    FakeToken token;
    LinkToken linkToken;
    ERC1967Proxy proxy;
    address lenderTreasury = address(1);
    address vendorTreasury = address(2);
    address wallet3 = address(3);
    address wallet4 = address(4);
    uint256 withdrawAmount = 5000;
    uint256 testAmount = 1000000000 gwei;
    uint256 testFee = 10;
    uint256 testFeeAmount = (testAmount * testFee) / 100;
    uint256 initialAmount = 2000000000 gwei;
    uint256 partialWithdrawAmount = (testAmount / 2);

    function setUp() public {
        Xscrow implementation = new Xscrow();
        token = new FakeToken("MATIC", "MATIC");
        linkToken = new LinkToken();
        operator = new FakeOperator(address(linkToken));
        oracle = new CreditOracle(
            LinkTokenInterface(address(linkToken)),
            address(operator),
            "",
            "http://withdrawurl.com",
            "http://executionurl.com"
        );
        bytes memory data = abi.encodeCall(
            implementation.initialize,
            (
                IERC20Upgradeable(address(token)),
                lenderTreasury,
                vendorTreasury,
                "xscrowTest",
                oracle,
                1000,
                2000000000 gwei
            )
        );
        proxy = new ERC1967Proxy(address(implementation), data);
        xscrow = Xscrow(payable(address(proxy)));
        xscrow.updateDepositFee(testFee);
        oracle.updateXscrow(IXscrow(address(xscrow)));
        token.mint(wallet3, initialAmount);
        linkToken.transfer(address(oracle), 10000000000 gwei);
    }

    function requestId() public returns (bytes32) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        return logs[6].topics[1];
    }

    function test_revertWithAddressZeroNotAllowed_initialize_token() public {
        Xscrow implementation = new Xscrow();
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        bytes memory data = abi.encodeCall(
            implementation.initialize,
            (
                IERC20Upgradeable(address(0)),
                lenderTreasury,
                vendorTreasury,
                "xscrowTest",
                oracle,
                1000,
                2000000000 gwei
            )
        );
        proxy = new ERC1967Proxy(address(implementation), data);
    }

    function test_revertWithAddressZeroNotAllowed_initialize_lender() public {
        Xscrow implementation = new Xscrow();
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        bytes memory data = abi.encodeCall(
            implementation.initialize,
            (
                IERC20Upgradeable(address(token)),
                address(0),
                vendorTreasury,
                "xscrowTest",
                oracle,
                1000,
                2000000000 gwei
            )
        );
        proxy = new ERC1967Proxy(address(implementation), data);
    }

    function test_revertWithAddressZeroNotAllowed_initialize_vendor() public {
        Xscrow implementation = new Xscrow();
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        bytes memory data = abi.encodeCall(
            implementation.initialize,
            (
                IERC20Upgradeable(address(token)),
                lenderTreasury,
                address(0),
                "xscrowTest",
                oracle,
                1000,
                2000000000 gwei
            )
        );
        proxy = new ERC1967Proxy(address(implementation), data);
    }

    function test_revertWithAddressZeroNotAllowed_initialize_oracle() public {
        Xscrow implementation = new Xscrow();
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        bytes memory data = abi.encodeCall(
            implementation.initialize,
            (
                IERC20Upgradeable(address(token)),
                lenderTreasury,
                vendorTreasury,
                "xscrowTest",
                Oracle(address(0)),
                1000,
                2000000000 gwei
            )
        );
        proxy = new ERC1967Proxy(address(implementation), data);
    }

    function test_revertWithFeeOutOfBounds_updateDepositFee() public {
        vm.expectRevert(Xscrow.FeeOutOfBounds.selector);
        xscrow.updateDepositFee(101);
    }

    function test_revertWithAddressZeroNotAllowed_updateLenderTreasury()
        public
    {
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        xscrow.updateLenderTreasury(address(0));
    }

    function test_revertWithAddressZeroNotAllowed_updateVendorTreasury()
        public
    {
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        xscrow.updateVendorTreasury(address(0));
    }

    function test_revertWithAddressZeroNotAllowed_updateNewXscrow() public {
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        xscrow.updateNewXscrow(NewXscrow(address(0)));
    }

    function test_revertWithAddressZeroNotAllowed_updateOracle() public {
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        xscrow.updateOracle(Oracle(address(0)));
    }

    function test_revertWithAddressZeroNotAllowed_migrateAll() public {
        xscrow.pause();
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        xscrow.migrateAll();
    }

    function test_revertWithNotOracle_executeDepositOf() public {
        vm.expectRevert(Xscrow.NotOracle.selector);
        xscrow.executeDepositOf(wallet3, true);
    }

    function test_revertWithNotOracle_partialWithdrawOf() public {
        vm.expectRevert(Xscrow.NotOracle.selector);
        xscrow.partialWithdrawOf(wallet3, withdrawAmount, true);
    }

    function test_revertWithNotOracle_withdrawOf() public {
        vm.expectRevert(Xscrow.NotOracle.selector);
        xscrow.withdrawOf(wallet3, true);
    }

    function test_revertWithNonZeroAmount_depositTo() public {
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        xscrow.depositTo(wallet3, 0);
    }

    function test_revertWithNonZeroAmount_requestWithdraw() public {
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        vm.prank(wallet3);
        xscrow.requestWithdraw();
    }

    function test_revertWithNonZeroAmount_requestPartialWithdraw() public {
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        vm.prank(wallet3);
        xscrow.requestPartialWithdraw(withdrawAmount);
    }

    function test_revertWithNonZeroAmount_requestExecuteDepositOf() public {
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        xscrow.requestExecuteDepositOf(wallet3);
    }

    function test_revertWithNonZeroAmount_partialWithdrawOf() public {
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        vm.prank(address(oracle));
        xscrow.partialWithdrawOf(wallet3, 0, true);
    }

    function test_revertWithNonZeroAmount_withdrawOf() public {
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        vm.prank(address(oracle));
        xscrow.withdrawOf(wallet3, true);
    }

    function test_revertWithNonZeroAmount_executeDepositOf() public {
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        vm.prank(address(oracle));
        xscrow.executeDepositOf(wallet3, true);
    }

    function test_revertWithMaximumDepositAmountExceeded_depositTo() public {
        vm.expectRevert(Xscrow.MaximumDepositAmountExceeded.selector);
        xscrow.depositTo(wallet3, 3000000000 gwei);
    }

    function test_revertWithInsufficientDepositAmount_depositTo() public {
        vm.expectRevert(Xscrow.InsufficientDepositAmount.selector);
        xscrow.depositTo(wallet3, 500);
    }

    function test_revertWithInsufficientDepositAmount_requestPartialWithdraw()
        public
    {
        vm.startPrank(wallet3);
        token.approve(address(xscrow), 1000000000 gwei);
        xscrow.deposit(1000000000 gwei);
        vm.expectRevert(Xscrow.NotEnoughBalance.selector);
        xscrow.requestPartialWithdraw(3000000000 gwei);
    }

    function test_emitDeposit_depositTo() public {
        vm.startPrank(wallet3);
        token.approve(address(xscrow), 1000000000 gwei);

        vm.expectEmit();
        emit Deposit(wallet3, 1000000000 gwei - testFeeAmount, wallet4);

        xscrow.depositTo(wallet4, 1000000000 gwei);

        assertEq(xscrow.balanceOf(wallet4), 1000000000 gwei - testFeeAmount);
        assertEq(token.balanceOf(wallet3), initialAmount - 1000000000 gwei);
    }

    function test_emitDeposit_deposit() public {
        vm.startPrank(wallet3);
        token.approve(address(xscrow), 1000000000 gwei);

        vm.expectEmit();
        emit Deposit(wallet3, 1000000000 gwei - testFeeAmount, wallet3);

        xscrow.deposit(1000000000 gwei);

        assertEq(xscrow.balanceOf(wallet3), 1000000000 gwei - testFeeAmount);
        assertEq(token.balanceOf(wallet3), initialAmount - 1000000000 gwei);
    }

    function test_emitDepositExecuted() public {
        vm.recordLogs();

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        vm.stopPrank();

        xscrow.requestExecuteDepositOf(wallet3);

        vm.expectEmit();
        emit DepositExecuted(wallet3, testAmount - testFeeAmount);
        operator.fulfillOracleRequest(requestId(), bytes32(uint256(1)));

        assertEq(token.balanceOf(lenderTreasury), testAmount - testFeeAmount);
        assertEq(xscrow.balanceOf(wallet3), 0);
    }

    function test_emitDepositExecutionNotAllowed() public {
        vm.recordLogs();

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        vm.stopPrank();

        xscrow.requestExecuteDepositOf(wallet3);

        vm.expectEmit();
        emit DepositExecutionNotAllowed(wallet3);
        operator.fulfillOracleRequest(requestId(), bytes32(uint256(0)));

        assertEq(token.balanceOf(lenderTreasury), 0);
        assertEq(xscrow.balanceOf(wallet3), testAmount - testFeeAmount);
    }

    function test_emitWithdrawSuccessful_requestWithdraw() public {
        vm.recordLogs();

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        xscrow.requestWithdraw();
        vm.stopPrank();

        vm.expectEmit();
        emit WithdrawSuccessful(wallet3, testAmount - testFeeAmount);
        operator.fulfillOracleRequest(requestId(), bytes32(uint256(1)));

        assertEq(token.balanceOf(wallet3), initialAmount - testFeeAmount);
        assertEq(xscrow.balanceOf(wallet3), 0);
    }

    function test_emitWithdrawNotAllowed_requestWithdraw() public {
        vm.recordLogs();

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        xscrow.requestWithdraw();
        vm.stopPrank();

        vm.expectEmit();
        emit WithdrawNotAllowed(wallet3, testAmount - testFeeAmount);
        operator.fulfillOracleRequest(requestId(), bytes32(uint256(0)));

        assertEq(token.balanceOf(wallet3), initialAmount - testAmount);
        assertEq(xscrow.balanceOf(wallet3), testAmount - testFeeAmount);
    }

    function test_emitWithdrawSuccessful_requestPartialWithdraw_partialAmount()
        public
    {
        vm.recordLogs();

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        xscrow.requestPartialWithdraw(partialWithdrawAmount);
        vm.stopPrank();

        vm.expectEmit();
        emit WithdrawSuccessful(wallet3, partialWithdrawAmount);
        operator.fulfillOracleRequest(requestId(), bytes32(uint256(1)));

        assertEq(
            token.balanceOf(wallet3),
            initialAmount - partialWithdrawAmount
        );
        assertEq(
            xscrow.balanceOf(wallet3),
            testAmount - testFeeAmount - partialWithdrawAmount
        );
    }

    function test_emitWithdrawSuccessful_requestPartialWithdraw_totalAmount()
        public
    {
        vm.recordLogs();

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        xscrow.requestPartialWithdraw(testAmount - testFeeAmount);
        vm.stopPrank();

        vm.expectEmit();
        emit WithdrawSuccessful(wallet3, testAmount - testFeeAmount);
        operator.fulfillOracleRequest(requestId(), bytes32(uint256(1)));

        assertEq(token.balanceOf(wallet3), initialAmount - testFeeAmount);
        assertEq(xscrow.balanceOf(wallet3), 0);
    }

    function test_emitWithdrawNotAllowed_requestPartialWithdraw() public {
        vm.recordLogs();

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        xscrow.requestPartialWithdraw(partialWithdrawAmount);
        vm.stopPrank();

        vm.expectEmit();
        emit WithdrawNotAllowed(wallet3, partialWithdrawAmount);
        operator.fulfillOracleRequest(requestId(), bytes32(uint256(0)));

        assertEq(token.balanceOf(wallet3), initialAmount - testAmount);
        assertEq(xscrow.balanceOf(wallet3), testAmount - testFeeAmount);
    }

    function test_emitXscrowMigrated_migrateAll() public {
        FakeNewXscrow newXscrow = new FakeNewXscrow();
        xscrow.updateNewXscrow(NewXscrow(address(newXscrow)));

        vm.startPrank(wallet3);
        token.approve(address(xscrow), testAmount);
        xscrow.deposit(testAmount);
        vm.stopPrank();

        xscrow.pause();

        vm.expectEmit();
        emit XscrowMigrated();
        xscrow.migrateAll();
    }

    function test_emitOracleUpdated_updateOracle() public {
        vm.expectEmit();
        emit OracleUpdated(address(oracle));
        xscrow.updateOracle(Oracle(address(oracle)));
    }

    function test_emitDepositFeeUpdated_updateDepositFee() public {
        vm.expectEmit();
        emit DepositFeeUpdated(5);
        xscrow.updateDepositFee(5);
    }

    function test_emitMinimumDepositAmountUpdated_updateMinimumDepositAmount()
        public
    {
        vm.expectEmit();
        emit MinimumDepositAmountUpdated(5000000000 gwei);
        xscrow.updateMinimumDepositAmount(5000000000 gwei);
    }

    function test_emitMaximumDepositAmountUpdated_updateMaximumDepositAmount()
        public
    {
        vm.expectEmit();
        emit MaximumDepositAmountUpdated(25000000000 gwei);
        xscrow.updateMaximumDepositAmount(25000000000 gwei);
    }

    function test_emitTokenBalanceReceived_receive() public {
        vm.startPrank(wallet3);

        DummyWallet wallet = new DummyWallet(xscrow);
        deal(address(wallet), testAmount);
        vm.expectEmit();
        emit TokenBalanceReceived(testAmount);

        wallet.send(testAmount);

        assertEq(address(xscrow).balance, testAmount);
    }

    function test_depositWithPermit() public {
        uint256 signerPrivateKey = 0xabc123;
        address signer = vm.addr(signerPrivateKey);

        token.mint(signer, initialAmount);

        assertEq(token.balanceOf(signer), initialAmount);

        sigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: signer,
            spender: address(xscrow),
            value: 2000000000 gwei,
            nonce: 0,
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        vm.prank(wallet4);
        xscrow.depositWithPermit(
            permit.owner,
            permit.value,
            permit.deadline,
            v,
            r,
            s
        );
        assertEq(token.balanceOf(signer), 0);
        assertEq(xscrow.balanceOf(signer), 1800000000 gwei);
        assertEq(token.balanceOf(xscrow.vendorTreasury()), 200000000 gwei);
    }

    function test_restore() public {
        xscrow.updateOldXscrow(wallet4);
        vm.startPrank(wallet4);
        xscrow.restore(
            Warranty(200000000 gwei, block.timestamp, block.timestamp),
            wallet3
        );
        assertEq(xscrow.balanceOf(wallet3), 200000000 gwei);
    }

    function test_revertWithZeroAmount_restore() public {
        xscrow.updateOldXscrow(wallet4);
        vm.startPrank(wallet4);
        vm.expectRevert(Xscrow.NonZeroAmount.selector);
        xscrow.restore(Warranty(0, block.timestamp, block.timestamp), wallet3);
        assertEq(xscrow.balanceOf(wallet3), 0);
    }

    function test_multiple_restore() public {
        xscrow.updateOldXscrow(wallet4);
        vm.startPrank(wallet4);
        uint256 anAmount = 200000000 gwei;
        xscrow.restore(
            Warranty(anAmount, block.timestamp, block.timestamp),
            wallet3
        );
        xscrow.restore(
            Warranty(anAmount, block.timestamp, block.timestamp),
            wallet3
        );
        assertEq(xscrow.balanceOf(wallet3), anAmount * 2);
    }

    function test_revertWithNotOldXscrow_restore() public {
        vm.expectRevert(Xscrow.NotOldXscrow.selector);
        xscrow.restore(
            Warranty(200000000 gwei, block.timestamp, block.timestamp),
            wallet3
        );
        assertEq(xscrow.balanceOf(wallet3), 0);
    }

    function test_updateOldXscrow() public {
        xscrow.updateOldXscrow(wallet3);
        assertEq(xscrow.oldXscrow(), wallet3);
    }

    function test_revertWithAddressZeroNotAllowed_updateOldXscrow() public {
        vm.expectRevert(Xscrow.AddressZeroNotAllowed.selector);
        xscrow.updateOldXscrow(address(0));
    }

    function test_revertNotOwner_updateOldXscrow() public {
        vm.startPrank(wallet4);
        vm.expectRevert("Ownable: caller is not the owner");
        xscrow.updateOldXscrow(wallet3);
    }
}
