import { expect } from 'chai';
import { ethers, upgrades } from 'hardhat';
import {
  CreditOracle,
  FakeNewXscrow,
  FakeOperator,
  FakeToken,
  LinkToken,
  Xscrow,
} from '../typechain-types';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { BigNumber, ContractTransaction } from 'ethers';

const xscrowContracts = [
  { type: 'Proxy', factory: 'Xscrow' },
  { type: 'Proxy', factory: 'FakeXscrowV2' },
];

xscrowContracts.forEach((xscrowContract) => {
  describe(`Xscrow - ${xscrowContract.factory}`, () => {
    let xscrow: Xscrow;
    let owner: SignerWithAddress;
    let wallet1: SignerWithAddress;
    let wallet2: SignerWithAddress;
    let lenderTreasury: SignerWithAddress;
    let vendorTreasury: SignerWithAddress;
    let fakeNewXscrow: FakeNewXscrow;
    let oracle: CreditOracle;
    let fakeLinkToken: LinkToken;
    let fakeToken: FakeToken;
    let fakeOperator: FakeOperator;
    let jobId: Uint8Array;
    let libIterableMapping: any;

    const testAmount = 5000000;
    const testFee = 2;
    const testFeeAmount = testAmount * (testFee / 100);
    const anApiUrl = 'https://anurl.com';
    const anExecutionApiUrl = 'https://an-execution-url.com';
    const pausableRejectedMsg = 'Pausable: paused';
    const notPausedRejectedMsg = 'Pausable: not paused';
    const ownableRejectedMsg = 'Ownable: caller is not the owner';
    const oracleRejectedMsg = 'Caller is not the oracle';
    const nonZeroAmountRejectedMsg = 'Deposit: amount must be > 0';
    const notEnoughBalanceRejectedMsg = 'Not enough balance';
    const zeroAddressMsg = 'Address can not be zero';
    const testIdentifier = 'token_xscrow';
    const zeroAddress = ethers.constants.AddressZero;
    const minimumDepositAmount = 1000000;
    const maximumDepositAmount = 10000000;

    const _requestIdOf = async (transaction: ContractTransaction) => {
      const transactionReceipt = await transaction.wait(1);
      return transactionReceipt.events![1].topics[1];
    };

    const _withdraw = async (oracleReturnData: boolean) => {
      await fakeOperator.fulfillOracleRequest(
        await _requestIdOf(await xscrow.connect(wallet1).requestWithdraw()),
        ethers.utils.defaultAbiCoder.encode(['bool'], [oracleReturnData])
      );
    };

    const _partialWithdraw = async (oracleReturnData: boolean, anAmount: number) => {
      await fakeOperator.fulfillOracleRequest(
        await _requestIdOf(await xscrow.connect(wallet1).requestPartialWithdraw(anAmount)),
        ethers.utils.defaultAbiCoder.encode(['bool'], [oracleReturnData])
      );
    };

    const _deposit = async (wallet: SignerWithAddress, anAmount: number) => {
      await fakeToken.mint(wallet.address, anAmount);
      await fakeToken.connect(wallet).approve(xscrow.address, anAmount);
      await xscrow.connect(wallet).deposit(anAmount);
    };
    const _depositTo = async (aSponsor: SignerWithAddress, anAmount: number, aPayee: SignerWithAddress) => {
      await fakeToken.mint(aSponsor.address, anAmount);
      await fakeToken.connect(aSponsor).approve(xscrow.address, anAmount);
      return xscrow.connect(aSponsor).depositTo(aPayee.address, anAmount);
    };

    const _requestExecuteDepositOf = async (oracleReturnData: boolean) => {
      await fakeOperator.fulfillOracleRequest(
        await _requestIdOf(await xscrow.requestExecuteDepositOf(wallet1.address)),
        ethers.utils.defaultAbiCoder.encode(['bool'], [oracleReturnData])
      );
    };

    const _deployXscrowWithProxy = async (initializeParams: any[]): Promise<Xscrow> => {
      return (await upgrades.deployProxy(
        await ethers.getContractFactory(xscrowContract.factory, {
          libraries: { IterableMapping: libIterableMapping.address },
        }),
        initializeParams,
        { initializer: 'initialize', kind: 'uups', unsafeAllowLinkedLibraries: true }
      )) as Xscrow;
    };

    beforeEach(async () => {
      jobId = ethers.utils.toUtf8Bytes('7da2702f37fd48e5b1b9a5715e3509b6');
      [owner, wallet1, wallet2, lenderTreasury, vendorTreasury] = await ethers.getSigners();
      fakeNewXscrow = await (await ethers.getContractFactory('FakeNewXscrow')).deploy();
      fakeLinkToken = await (await ethers.getContractFactory('LinkToken')).deploy();
      fakeOperator = await (await ethers.getContractFactory('FakeOperator')).deploy(fakeLinkToken.address);
      fakeToken = await (await ethers.getContractFactory('FakeToken')).deploy('TokenX', 'TKX');
      libIterableMapping = await (await ethers.getContractFactory('IterableMapping')).deploy();

      oracle = await (
        await ethers.getContractFactory('CreditOracle')
      ).deploy(fakeLinkToken.address, fakeOperator.address, jobId, anApiUrl, anExecutionApiUrl);

      xscrow = await _deployXscrowWithProxy([
        fakeToken.address,
        lenderTreasury.address,
        vendorTreasury.address,
        testIdentifier,
        oracle.address,
        minimumDepositAmount,
        maximumDepositAmount,
      ]);

      await xscrow.updateDepositFee(testFee);
      await oracle.updateXscrow(xscrow.address);

      await fakeLinkToken.connect(owner).transfer(oracle.address, '1000000000000000000');
    });

    describe('deploy settings', () => {
      it('new', () => {
        expect(xscrow).to.not.be.null;
      });

      it('should not initialize twice', async () => {
        await expect(
          xscrow.initialize(
            fakeToken.address,
            lenderTreasury.address,
            vendorTreasury.address,
            testIdentifier,
            oracle.address,
            minimumDepositAmount,
            maximumDepositAmount
          )
        ).to.revertedWith('Initializable: contract is already initialized');
      });

      it('ownership', async () => {
        expect(await xscrow.owner()).to.be.equal(owner.address);
      });

      it('token address', async () => {
        expect(await xscrow.tokenAddress()).to.be.equal(fakeToken.address);
      });

      it('identifier', async () => {
        expect(await xscrow.identifier()).to.be.equal(testIdentifier);
      });

      it('oracle', async () => {
        expect(await xscrow.oracle()).to.be.equal(oracle.address);
      });

      it('minimumDepositAmount', async () => {
        expect(await xscrow.minimumDepositAmount()).to.be.equal(minimumDepositAmount);
      });

      it('maximumDepositAmount', async () => {
        expect(await xscrow.maximumDepositAmount()).to.be.equal(maximumDepositAmount);
      });
    });

    describe('initialize', () => {
      it('token zero address', async () => {
        await expect(
          _deployXscrowWithProxy([
            zeroAddress,
            lenderTreasury.address,
            vendorTreasury.address,
            testIdentifier,
            oracle.address,
            minimumDepositAmount,
            maximumDepositAmount,
          ])
        ).to.revertedWith(zeroAddressMsg);
      });

      it('lender treasury zero address', async () => {
        await expect(
          _deployXscrowWithProxy([
            fakeToken.address,
            zeroAddress,
            vendorTreasury.address,
            testIdentifier,
            oracle.address,
            minimumDepositAmount,
            maximumDepositAmount,
          ])
        ).to.revertedWith(zeroAddressMsg);
      });

      it('vendor treasury zero address', async () => {
        await expect(
          _deployXscrowWithProxy([
            fakeToken.address,
            lenderTreasury.address,
            zeroAddress,
            testIdentifier,
            oracle.address,
            minimumDepositAmount,
            maximumDepositAmount,
          ])
        ).to.revertedWith(zeroAddressMsg);
      });

      it('oracle zero address', async () => {
        await expect(
          _deployXscrowWithProxy([
            fakeToken.address,
            lenderTreasury.address,
            vendorTreasury.address,
            testIdentifier,
            zeroAddress,
            minimumDepositAmount,
            maximumDepositAmount,
          ])
        ).to.revertedWith(zeroAddressMsg);
      });
    });

    describe('pausable', () => {
      it('xscrow is not paused by default', async () => {
        expect(await xscrow.paused()).to.equal(false);
      });

      it('xscrow is paused', async () => {
        await xscrow.pause();

        expect(await xscrow.paused()).to.equal(true);
      });

      it('xscrow is only allow pause by contract owner', async () => {
        await expect(xscrow.connect(wallet1).pause()).to.rejectedWith(ownableRejectedMsg);
      });

      it('xscrow is only allow unpause by contract owner', async () => {
        await xscrow.pause();

        await expect(xscrow.connect(wallet1).unpause()).to.rejectedWith(ownableRejectedMsg);
      });

      it('xscrow is unpaused', async () => {
        await xscrow.pause();

        await xscrow.unpause();

        expect(await xscrow.paused()).to.equal(false);
      });

      it('request withdraw is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.requestWithdraw()).to.rejectedWith(pausableRejectedMsg);
      });

      it('withdraw of is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.withdrawOf(wallet1.address, true)).to.rejectedWith(pausableRejectedMsg);
      });

      it('request partial withdraw is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.requestPartialWithdraw(100)).to.rejectedWith(pausableRejectedMsg);
      });

      it('partial withdraw is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.partialWithdrawOf(wallet1.address, 100, true)).to.rejectedWith(pausableRejectedMsg);
      });

      it('deposits is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.deposit(1000)).to.rejectedWith(pausableRejectedMsg);
      });

      it('deposit to is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.depositTo(wallet1.address, 1000)).to.rejectedWith(pausableRejectedMsg);
      });

      it('executeDepositOf is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.executeDepositOf(wallet1.address, true)).to.rejectedWith(pausableRejectedMsg);
      });

      it('requestExecuteDepositOf is not allowed on xscrow paused', async () => {
        await xscrow.pause();

        await expect(xscrow.requestExecuteDepositOf(wallet1.address)).to.rejectedWith(pausableRejectedMsg);
      });

      it('migrateAll is not allowed on xscrow not paused', async () => {
        await expect(xscrow.migrateAll()).to.rejectedWith(notPausedRejectedMsg);
      });
    });

    describe('execute deposit of', () => {
      it('request execute deposit of', async () => {
        await new Promise(async (resolve, reject) => {
          const filter = xscrow.filters.DepositExecuted(wallet1.address);
          xscrow.once(filter, async (aPayee: any) => {
            try {
              expect(await fakeToken.balanceOf(lenderTreasury.address)).to.equal(testAmount - testFeeAmount);
              expect(await xscrow.balanceOf(aPayee)).to.equal(0);
              resolve(true);
            } catch (e) {
              reject(e);
            }
          });

          await _deposit(wallet1, testAmount);
          await _requestExecuteDepositOf(true);
        });
      });

      it('request execute deposit of not allowed', async () => {
        await new Promise(async (resolve, reject) => {
          const filter = xscrow.filters.DepositExecutionNotAllowed(wallet1.address);
          xscrow.once(filter, async (aPayee: any) => {
            try {
              expect(await fakeToken.balanceOf(lenderTreasury.address)).to.equal(0);
              expect(await xscrow.balanceOf(aPayee)).to.equal(testAmount - testFeeAmount);
              resolve(true);
            } catch (e) {
              reject(e);
            }
          });

          await _deposit(wallet1, testAmount);
          await _requestExecuteDepositOf(false);
        });
      });

      it('request execute deposit not owner', async () => {
        await _deposit(wallet1, testAmount);
        const _contract = xscrow.connect(wallet2);
        await expect(_contract.requestExecuteDepositOf(wallet1.address)).to.revertedWith(ownableRejectedMsg);
      });

      it('execute deposit of is not allowed if not oracle', async () => {
        await expect(xscrow.executeDepositOf(wallet1.address, true)).to.rejectedWith(oracleRejectedMsg);
      });

      it('request execute deposit of without balance', async () => {
        await expect(xscrow.requestExecuteDepositOf(wallet1.address)).rejectedWith(nonZeroAmountRejectedMsg);
      });

      it('remove warranty on execute deposit', async () => {
        await _deposit(wallet1, testAmount);
        await _withdraw(true);
        const warranty = await xscrow.warranty(wallet1.address);
        expect(warranty.created_at).to.equal(BigNumber.from('0'));
        expect(warranty.updated_at).to.equal(BigNumber.from('0'));
        expect(warranty.amount).to.equal(BigNumber.from('0'));
      });
    });

    describe('deposits', () => {
      it('deposit event', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.Deposit(wallet1.address);
          xscrow.once(filter, async (aPayee: any, anAmount: any, aSponsor: any) => {
            expect(aPayee).to.equal(wallet1.address);
            expect(aSponsor).to.equal(wallet2.address);
            expect(await xscrow.balanceOf(aPayee)).to.equal(0);
            expect(await xscrow.balanceOf(aSponsor)).to.equal(testAmount - testFeeAmount);
            expect(anAmount.toNumber()).to.equal(testAmount - testFeeAmount);
            resolve(true);
          });

          await _depositTo(wallet1, testAmount, wallet2);
        });
      });

      it('reverted deposit amount 0', async () => {
        await expect(xscrow.connect(wallet1).deposit(0)).to.rejectedWith(nonZeroAmountRejectedMsg);
      });

      it('deposit to', async () => {
        await _depositTo(wallet1, testAmount, wallet2);

        expect(await fakeToken.balanceOf(wallet1.address)).to.equal(0);
        expect(await fakeToken.balanceOf(lenderTreasury.address)).to.equal(0);
        expect(await fakeToken.balanceOf(vendorTreasury.address)).to.equal(testFeeAmount);
        expect(await fakeToken.balanceOf(xscrow.address)).to.equal(testAmount - testFeeAmount);
        expect(await xscrow.balanceOf(wallet2.address)).to.equal(testAmount - testFeeAmount);
        expect(await xscrow.balanceOf(wallet1.address)).to.equal(0);
      });

      it('deposit to exceeds maximum', async () => {
        await expect(_depositTo(wallet1, 100000000, wallet2)).to.revertedWith('Exceeded maximum deposit amount');
      });

      it('deposit to insufficient amount', async () => {
        await expect(_depositTo(wallet1, 10000, wallet2)).to.revertedWith('Insufficient deposit amount');
      });

      it('deposit', async () => {
        await _deposit(wallet1, testAmount);

        expect(await fakeToken.balanceOf(wallet1.address)).to.equal(0);
        expect(await fakeToken.balanceOf(lenderTreasury.address)).to.equal(0);
        expect(await fakeToken.balanceOf(vendorTreasury.address)).to.equal(testFeeAmount);
        expect(await xscrow.balanceOf(wallet1.address)).to.equal(testAmount - testFeeAmount);
        expect(await fakeToken.balanceOf(xscrow.address)).to.equal(testAmount - testFeeAmount);
      });

      it('deposit with zero fee', async () => {
        await xscrow.updateDepositFee(0);
        await _deposit(wallet1, testAmount);

        expect(await fakeToken.balanceOf(wallet1.address)).to.equal(0);
        expect(await fakeToken.balanceOf(lenderTreasury.address)).to.equal(0);
        expect(await fakeToken.balanceOf(vendorTreasury.address)).to.equal(0);
        expect(await xscrow.balanceOf(wallet1.address)).to.equal(testAmount);
        expect(await fakeToken.balanceOf(xscrow.address)).to.equal(testAmount);
      });

      it('multiple deposits', async () => {
        await fakeToken.mint(wallet1.address, testAmount * 2);
        await fakeToken.connect(wallet1).approve(xscrow.address, testAmount * 2);

        await xscrow.connect(wallet1).deposit(testAmount);
        await xscrow.connect(wallet1).deposit(testAmount);

        expect(await fakeToken.balanceOf(wallet1.address)).to.equal(0);
        expect(await fakeToken.balanceOf(xscrow.address)).to.equal((testAmount - testFeeAmount) * 2);
        expect(await xscrow.balanceOf(wallet1.address)).to.equal((testAmount - testFeeAmount) * 2);
        expect(await fakeToken.balanceOf(vendorTreasury.address)).to.equal(testFeeAmount * 2);
      });

      it('balanceOf', async () => {
        expect(await xscrow.balanceOf(wallet2.address)).to.equal(0);
      });

      it('set dates on first deposit', async () => {
        await _deposit(wallet1, testAmount);

        const warranty = await xscrow.warranty(wallet1.address);

        expect(warranty.updated_at).to.equal(warranty.created_at);
        expect(warranty.updated_at).not.to.equal(BigNumber.from('0'));
        expect(warranty.created_at).not.to.equal(BigNumber.from('0'));
      });

      it('update dates on multiple deposits', async () => {
        await _deposit(wallet1, testAmount);
        const oldStateWarranty = await xscrow.warranty(wallet1.address);
        await _deposit(wallet1, testAmount);
        const warranty = await xscrow.warranty(wallet1.address);

        expect(warranty.updated_at).not.to.equal(warranty.created_at);
        expect(warranty.updated_at).not.to.equal(BigNumber.from('0'));
        expect(warranty.created_at).not.to.equal(BigNumber.from('0'));
        expect(warranty.updated_at).to.greaterThan(oldStateWarranty.updated_at);
      });
    });

    describe('withdraw', () => {
      it('request withdraw not allowed', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.WithdrawNotAllowed(wallet1.address);
          xscrow.once(filter, async (aPayee: any, anAmount: any) => {
            expect(wallet1.address).to.equal(aPayee);
            expect(anAmount).to.equal(await xscrow.balanceOf(wallet1.address));
            resolve(true);
          });

          await _deposit(wallet1, testAmount);
          await _withdraw(false);
        });
      });

      it('request withdraw', async () => {
        await new Promise(async (resolve, reject) => {
          const filter = xscrow.filters.WithdrawSuccessful(wallet1.address);
          xscrow.once(filter, async (aPayee: any, anAmount: any) => {
            try {
              expect(await fakeToken.balanceOf(aPayee)).to.equal(testAmount - testFeeAmount);
              expect(await xscrow.balanceOf(aPayee)).to.equal(0);
              expect(testAmount - testFeeAmount).to.equal(anAmount);
              resolve(true);
            } catch (error) {
              reject(error);
            }
          });

          await _deposit(wallet1, testAmount);
          await _withdraw(true);
        });
      });

      it('withdraw of is not allowed if not oracle', async () => {
        await expect(xscrow.withdrawOf(wallet1.address, true)).to.rejectedWith(oracleRejectedMsg);
      });

      it('request withdraw without balance', async () => {
        await expect(xscrow.connect(wallet1).requestWithdraw()).rejectedWith(nonZeroAmountRejectedMsg);
      });

      it('remove warranty on execute deposit', async () => {
        await _deposit(wallet1, testAmount);
        await _requestExecuteDepositOf(true);
        const warranty = await xscrow.warranty(wallet1.address);
        expect(warranty.created_at).to.equal(BigNumber.from('0'));
        expect(warranty.updated_at).to.equal(BigNumber.from('0'));
        expect(warranty.amount).to.equal(BigNumber.from('0'));
      });
    });

    describe('partial withdraw', () => {
      it('request partial withdraw not allowed', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.WithdrawNotAllowed(wallet1.address);
          xscrow.once(filter, (aPayee: any, anAmount: any) => {
            expect(wallet1.address).to.equal(aPayee);
            expect(anAmount).to.equal(1000);
            resolve(true);
          });

          await _deposit(wallet1, testAmount);
          await _partialWithdraw(false, 1000);
        });
      });

      it('request partial withdraw', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.WithdrawSuccessful(wallet1.address);
          xscrow.once(filter, async (aPayee: any, anAmount: any) => {
            expect(await fakeToken.balanceOf(aPayee)).to.equal(anAmount);
            expect(await xscrow.balanceOf(aPayee)).to.equal(testAmount - testFeeAmount - anAmount);
            resolve(true);
          });

          await _deposit(wallet1, testAmount);
          await _partialWithdraw(true, 4500);
        });
      });

      it('request partial withdraw with maximum amount', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.WithdrawSuccessful(wallet1.address);
          xscrow.once(filter, async (aPayee: any, anAmount: any) => {
            expect(await fakeToken.balanceOf(aPayee)).to.equal(anAmount);
            expect(await xscrow.balanceOf(aPayee)).to.equal(0);
            resolve(true);
          });

          await _deposit(wallet1, testAmount);
          await _partialWithdraw(true, testAmount - testFeeAmount);
        });
      });

      it('partial withdraw of is not allowed if not oracle', async () => {
        await expect(xscrow.partialWithdrawOf(wallet1.address, 1000, true)).to.rejectedWith(oracleRejectedMsg);
      });

      it('request partial withdraw without balance', async () => {
        await expect(xscrow.connect(wallet1).requestPartialWithdraw(100)).rejectedWith(nonZeroAmountRejectedMsg);
      });

      it('request partial withdraw maximum exceeded', async () => {
        await _deposit(wallet1, testAmount);
        await expect(xscrow.connect(wallet1).requestPartialWithdraw(testAmount + 1000)).rejectedWith(
          notEnoughBalanceRejectedMsg
        );
      });

      it('remove warranty on partial withdraw with all balance', async () => {
        await _deposit(wallet1, testAmount);
        await _partialWithdraw(true, testAmount - testFeeAmount);
        const warranty = await xscrow.warranty(wallet1.address);
        expect(warranty.created_at).to.equal(BigNumber.from('0'));
        expect(warranty.updated_at).to.equal(BigNumber.from('0'));
        expect(warranty.amount).to.equal(BigNumber.from('0'));
      });
    });

    describe('migration', () => {
      it('migrate', async () => {
        await xscrow.updateNewXscrow(fakeNewXscrow.address);
        await _deposit(wallet1, testAmount);
        await xscrow.pause();

        await xscrow.connect(wallet1).migrate();

        expect(await xscrow.balanceOf(wallet1.address)).to.equal(0);
        expect(await fakeToken.balanceOf(xscrow.address)).to.equal(0);
        expect(await fakeToken.balanceOf(fakeNewXscrow.address)).to.equal(testAmount - testFeeAmount);
      });

      it('cannot migrate if user doesn\'t have a warranty', async () => {
        await xscrow.updateNewXscrow(fakeNewXscrow.address);
        await _deposit(wallet1, testAmount);
        const balance = await xscrow.balanceOf(wallet1.address);
        await xscrow.pause();

        await xscrow.connect(wallet2).migrate();

        expect(await xscrow.balanceOf(wallet2.address)).to.equal(0);
        expect(await xscrow.balanceOf(wallet1.address)).to.equal(balance);
        expect(await fakeToken.balanceOf(fakeNewXscrow.address)).to.equal(0);
        expect(await fakeToken.balanceOf(xscrow.address)).to.equal(testAmount - testFeeAmount);
      });

      it('migrateAll', async () => {
        await xscrow.updateNewXscrow(fakeNewXscrow.address);
        await _deposit(wallet1, testAmount);
        await _deposit(wallet2, testAmount);
        const balanceBeforeMigration = await fakeToken.balanceOf(xscrow.address);
        await xscrow.pause();

        await xscrow.migrateAll();

        expect(await xscrow.migrated()).to.equal(true);
        expect(await fakeToken.balanceOf(xscrow.address)).to.equal(0);
        expect(await fakeToken.balanceOf(fakeNewXscrow.address)).to.equal(balanceBeforeMigration);
      });

      it('newXscrow is not set migrateAll can be reverted', async () => {
        await xscrow.pause();

        await expect(xscrow.migrateAll()).to.revertedWith(zeroAddressMsg) ;
      });

      it('only owner can migrateAll', async () => {
        await xscrow.pause();
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.migrateAll()).to.revertedWith(ownableRejectedMsg) ;
      });


      it('migrate xscrow event', async () => {
        await new Promise(async (resolve) => {
          xscrow.once(xscrow.filters.XscrowMigrated(), () => {
            expect(true).to.equal(true);
            resolve(true);
          });
          await xscrow.updateNewXscrow(fakeNewXscrow.address);
          await _deposit(wallet1, testAmount);
          await xscrow.pause();

          await xscrow.migrateAll();
        });
      });
    });

    describe('updatable properties', () => {
      it('owner can update lenderTreasury', async () => {
        await xscrow.updateLenderTreasury(wallet1.address);

        expect(await xscrow.lenderTreasury()).to.equal(wallet1.address);
      });

      it('not owner cannot update lenderTreasury', async () => {
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.updateLenderTreasury(wallet1.address)).to.revertedWith(ownableRejectedMsg);
      });

      it('lenderTreasury with zero address', async () => {
        await expect(xscrow.updateLenderTreasury(zeroAddress)).to.revertedWith(zeroAddressMsg);
      });

      it('owner can update vendor treasury', async () => {
        await xscrow.updateVendorTreasury(wallet1.address);

        expect(await xscrow.vendorTreasury()).to.equal(wallet1.address);
      });

      it('not owner cannot update vendor treasury', async () => {
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.updateVendorTreasury(wallet1.address)).to.revertedWith(ownableRejectedMsg);
      });

      it('vendor treasury with zero address', async () => {
        await expect(xscrow.updateVendorTreasury(zeroAddress)).to.revertedWith(zeroAddressMsg);
      });

      it('owner can update oracle', async () => {
        await xscrow.updateOracle(oracle.address);

        expect(await xscrow.oracle()).to.equal(oracle.address);
      });

      it('not owner cannot update oracle', async () => {
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.updateOracle(wallet1.address)).to.revertedWith(ownableRejectedMsg);
      });

      it('update oracle event', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.OracleUpdated(wallet1.address);
          xscrow.once(filter, (oracle: any) => {
            expect(wallet1.address).to.equal(oracle);
            resolve(true);
          });

          await xscrow.updateOracle(wallet1.address);
        });
      });

      it('oracle with zero address', async () => {
        await expect(xscrow.updateOracle(zeroAddress)).to.revertedWith(zeroAddressMsg);
      });

      it('owner can update deposit fee', async () => {
        await xscrow.updateDepositFee(1);

        expect(await xscrow.depositFee()).to.equal(1);
      });

      it('owner cannot update deposit fee with wrong value', async () => {
        await expect(xscrow.updateDepositFee(-1)).to.rejectedWith('value out-of-bounds');
        await expect(xscrow.updateDepositFee(101)).to.revertedWith('Fee value out-of-bounds');
        expect(await xscrow.depositFee()).to.equal(testFee);
      });

      it('not owner cannot update deposit fee', async () => {
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.updateDepositFee(1)).to.revertedWith(ownableRejectedMsg);
      });

      it('update deposit fee event', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.DepositFeeUpdated();
          xscrow.once(filter, (anAmount: any) => {
            expect(anAmount).to.equal(testFee);
            resolve(true);
          });

          await xscrow.updateDepositFee(testFee);
        });
      });

      it('owner can update minimumDepositAmount', async () => {
        await xscrow.updateMinimumDepositAmount(100);

        expect(await xscrow.minimumDepositAmount()).to.equal(BigNumber.from('100'));
      });

      it('not owner cannot update minimumDepositAmount', async () => {
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.updateMinimumDepositAmount(100)).to.revertedWith(ownableRejectedMsg);
      });

      it('update minimumDepositAmount event', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.MinimumDepositAmountUpdated();
          xscrow.once(filter, (anAmount: any) => {
            expect(anAmount).to.equal(50);
            resolve(true);
          });

          await xscrow.updateMinimumDepositAmount(50);
        });
      });

      it('owner can update maximumDepositAmount', async () => {
        await xscrow.updateMaximumDepositAmount(100);

        expect(await xscrow.maximumDepositAmount()).to.equal(BigNumber.from('100'));
      });

      it('not owner cannot update maximumDepositAmount', async () => {
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.updateMaximumDepositAmount(100)).to.revertedWith(ownableRejectedMsg);
      });

      it('update maximumDepositAmount event', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.MaximumDepositAmountUpdated();
          xscrow.once(filter, (anAmount: any) => {
            expect(anAmount).to.equal(50);
            resolve(true);
          });

          await xscrow.updateMaximumDepositAmount(50);
        });
      });

      it('owner can update new xscrow', async () => {
        await xscrow.updateNewXscrow(fakeNewXscrow.address);

        expect(await xscrow.newXscrow()).to.equal(fakeNewXscrow.address);
      });

      it('owner cannot update new xscrow if address is zero', async () => {
        await expect(xscrow.updateNewXscrow(ethers.constants.AddressZero)).to.revertedWith(zeroAddressMsg);
      });

      it('not owner cannot update new xscrow', async () => {
        const _contract = xscrow.connect(wallet2);

        await expect(_contract.updateNewXscrow(fakeNewXscrow.address)).to.revertedWith(ownableRejectedMsg);
      });
    });

    describe('fallback - receive', () => {
      it('token balance received event when receive', async () => {
        await new Promise(async (resolve) => {
          const filter = xscrow.filters.TokenBalanceReceived();
          xscrow.once(filter, (anAmount: any) => {
            expect(anAmount).to.equal(testAmount);
            resolve(true);
          });

          await wallet1.sendTransaction({ to: xscrow.address, value: testAmount });
        });
      });

      it('revert when fallback', async () => {
        await expect(
          wallet1.sendTransaction({
            to: xscrow.address,
            value: '110000',
            data: ethers.utils.defaultAbiCoder.encode(['bool'], [true]),
          })
        ).to.reverted;
      });
    });
  });
});
