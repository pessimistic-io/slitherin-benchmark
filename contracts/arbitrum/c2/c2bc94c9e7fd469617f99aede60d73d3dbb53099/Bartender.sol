//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Sake} from "./Sake.sol";
import {Constant} from "./Constant.sol";
import {IBartender, IERC20, UserDepositInfo, SakeVaultInfo, UpdatedDebtRatio} from "./IBartender.sol";
import {IWater} from "./IWater.sol";
import {IVault} from "./IVault.sol";
import {Math} from "./Math.sol";
import {FeeSplitStrategy} from "./FeeSplitStrategy.sol";

/**
 * @author Chef Photons, Vaultka Team serving high quality drinks; drink responsibly.
 * Factory and global config params
 */
contract Bartender is IBartender, Ownable, Constant {
    // using SafeERC20 for IERC20;
    using Math for uint256;
    using FeeSplitStrategy for FeeSplitStrategy.Info;

    FeeSplitStrategy.Info private feeSplitStrategy;
    IERC20 public immutable usdcToken;
    address public velaMintBurnVault;
    address public vlp;
    address public velaStakingVault;
    address private water;
    address private keeper;
    address private liquor;
    bool private feeEnabled;
    address private feeRecipient;
    uint96 private feeBPS = 0; // 0.5%
    uint256 private _totalSupply;
    uint256 private _currentId;

    mapping(uint256 => address) internal sakeVault;
    mapping(uint256 => UpdatedDebtRatio) internal updatedDebtRatio;
    mapping(address => mapping(uint256 => UserDepositInfo)) internal userDepositInfo;
    mapping(uint256 => SakeVaultInfo) internal sakeVaultInfo;

    constructor(
        address _usdcToken, 
        address _water, 
        address _keeper, 
        address _liquor, 
        address _feeRecipient,
        address _mintAndBurn,
        address stakingVault,
        address _vlp) {
        keeper = _keeper;
        usdcToken = IERC20(_usdcToken);
        water = _water;
        liquor = _liquor;
        feeRecipient = _feeRecipient;
        _currentId = 1;
        feeEnabled = true;
        velaMintBurnVault = _mintAndBurn;
        velaStakingVault = stakingVault;
        vlp = _vlp;
        usdcToken.approve(water, type(uint256).max);
    }

    /* ##################################################################
                                MODIFIERS
    ################################################################## */
    modifier onlyKeeper() {
        if (keeper != msg.sender) revert BTDNotAKeeper();
        _;
    }

    modifier onlyLiquor() {
        if (liquor != msg.sender) revert BTDNotLiquor();
        _;
    }

    /* ##################################################################
                                OWNER FUNCTIONS
    ################################################################## */
    // / @notice update every address with a single function in other to reduce deployment fees
    // / @param what bytes32 of the values to update.
    // / @param value address of the bytes32 to update with.
    // function settingManager(bytes32 what, address value) external onlyOwner {
    //     if (value == address(0)) revert ThrowZeroAddress();
    //     if (what == "keeper") keeper = value;
    //     else if (what == "water") water = value;
    //     else if (what == "fee") feeRecipient = value;
    //     else if (what == "liquor") liquor = value;
    //     else revert InvalidParameter(what);
    //     emit SettingManager(what, value);
    // }

    // @notice sets feeBps
    // @param _feeBps the part of USDC that will be deducted as protocol fees
    function setFeeParams(uint16 _feeBps) external onlyOwner {
        if (_feeBps > MAX_BPS) revert InvalidFeeBps();
        feeBPS = _feeBps;
    }

    // / @notice update every bool with a single function in other to reduce deployment fees
    // / @param what bytes32 of the values to update.
    // / @param value bool of the bytes32 to update with.
    // function settingManagerForBool(bytes32 what, bool value) external onlyOwner {
    //     if (what == "fee") feeEnabled = value;
    //     else revert InvalidParameter(what);
    //     emit SettingManagerForBool(what, value);
    // }

    // function settingManagerForVELA(address _mintAndBurn, address stakingVault, address _vlp) external onlyOwner {
    //     velaMintBurnVault = _mintAndBurn;
    //     velaStakingVault = stakingVault;
    //     vlp = _vlp;
    // }

    /// @notice updates fee split strategy
    /// @notice this determines how eth rewards should be split between WATER Vault and BARTENDER
    /// @notice basis the utilization of WATER Vault
    /// @param _feeStrategy: new fee strategy
    function updateFeeStrategyParams(FeeSplitStrategy.Info calldata _feeStrategy) external onlyOwner {
        feeSplitStrategy = _feeStrategy;
    }

    /* ##################################################################
                                KEEPER FUNCTIONS
    ################################################################## */
    /// @notice Create new SAKE Vault
    function createSake() external onlyKeeper {
        if (liquor == address(0)) revert ThrowZeroAddress();

        uint256 lCurrentId = _currentId;
        // compute the amount deposited with the last known time
        uint256 _amount = sakeVaultInfo[lCurrentId].totalAmountOfUSDCWithoutLeverage * 3;
        // revert if no deposit occure
        if (_amount == 0) revert CurrentDepositIsZero();

        // create new SAKE
        Sake newSake = new Sake(
            address(usdcToken),
            water,
            address(this),
            velaMintBurnVault,
            velaStakingVault,
            vlp,
            liquor
        );

        sakeVault[lCurrentId] = address(newSake);
        // transfer _token into the newly created SAKE
        usdcToken.transfer(address(newSake), _amount);
        uint256 totalVLP = _initializedMintAndStake(newSake);
        sakeVaultInfo[lCurrentId].totalAmountOfVLP = totalVLP;
        sakeVaultInfo[lCurrentId].totalAmountOfVLPInUSDC = convertVLPToUSDC(totalVLP);
        sakeVaultInfo[lCurrentId].startTime = block.timestamp;
        // store puchase price
        sakeVaultInfo[lCurrentId].purchasePrice = getVLPPrice();
        initializedAllSakeUsersShares(lCurrentId);
        storeDebtRatio(lCurrentId, 0);
        _currentId++;
        emit CreateNewSAKE(address(newSake), lCurrentId);
    }

    /* ##################################################################
                                SAKE FUNCTIONS
    ################################################################## */
    /// @notice initializing mint and stake on `_sake`
    function _initializedMintAndStake(Sake _sake) private returns (uint256) {
        (bool _status, uint256 totalVLP) = _sake.executeMintAndStake();
        if (!_status) revert UnsuccessfulCreationOfSake();
        return totalVLP;
    }

    /* ##################################################################
                                USER FUNCTIONS
    ################################################################## */
    /** @dev See {IBartender-deposit}. */
    function deposit(uint256 _amount, address _receiver) external {
        if (_amount == 0) revert ThrowZeroAmount();
        usdcToken.transferFrom(msg.sender, address(this), _amount);
        if (feeEnabled) {
            // take protocol fee
            _amount = takeFees(_amount);
        }
        uint256 initialDeposit = userDepositInfo[_receiver][_currentId].amount;
        // locally store 2X leverage to avoid computing mload everytime
        uint256 leverage = _amount * 2;
        // take leverage from WATER VAULT
        IWater(water).leverageVault(leverage);
        uint256 lCurrentId = _currentId;
        // update total amount without borrowed amount
        sakeVaultInfo[lCurrentId].totalAmountOfUSDCWithoutLeverage += _amount;
        // update amount stake on current time interval
        sakeVaultInfo[lCurrentId].leverage += leverage;
        // update user state values
        userDepositInfo[_receiver][lCurrentId].amount += _amount;
        // push users into list
        if (initialDeposit == 0) {
            sakeVaultInfo[lCurrentId].users.push(_receiver);
        }
        emit BartenderDeposit(msg.sender, _amount, lCurrentId, leverage);
    }

    /** @dev See {IBartender-withdraw}. */
    function withdraw(uint256 _amount, uint256 id, address _receiver) external {
        if (sakeVaultInfo[id].isLiquidated) revert ThrowLiquidated();

        if (_amount == 0) revert ThrowZeroAmount();

        // if (block.timestamp < sakeVaultInfo[id].startTime + COOLDOWN_PERIOD) revert ThrowLockTimeOn();

        if (_amount > previewWithdraw(id, msg.sender)) revert ThrowInvalidAmount();

        uint256 withdrawableAmountInVLP = computesAmountToBeSoldInVLPUpdateShareAndDebtRatio(_amount, id, msg.sender);
        address _sake = sakeVault[id];
        (bool status, uint256 _withdrawnAmountinUSDC) = Sake(_sake).withdraw(address(this), withdrawableAmountInVLP);
        if (!status) revert SakeWitdrawal({sake: _sake, amount: _amount});
        _transferAndRepayLoan(_withdrawnAmountinUSDC, _receiver, _amount);
        emit Withdraw(msg.sender, _amount, id, withdrawableAmountInVLP);
    }

    /* ##################################################################
                                INTERNAL FUNCTIONS
    ################################################################## */
    // transfer and repay load
    function _transferAndRepayLoan(uint256 _withdrawnAmountinUSDC, address _receiver, uint256 share) private {
        uint256 loan = (_withdrawnAmountinUSDC - share);
        // repay loan to WATER VAULT
        IWater(water).repayDebt(loan);
        // take protocol fee
        if (feeEnabled) {
            // take protocol fee
            share = takeFees(share);
        }
        usdcToken.transfer(_receiver, share);
    }

    // take protocol fees
    function takeFees(uint256 _amount) private returns (uint256 amount) {
        // take protocol fee
        uint256 _protocolFee = (_amount * feeBPS) / MAX_BPS;
        // amount sub fee
        amount = _amount - _protocolFee;
        // feeRecipient share
        usdcToken.transfer(feeRecipient, _protocolFee);
    }

    // convert totalVLP to USDC
    function convertVLPToUSDC(uint256 _amount) private view returns (uint256) {
        uint256 _vlpPrice = getVLPPrice();
        return _amount.mulDiv(_vlpPrice * 10, (10 ** VLP_DECIMAL));
    }

    function getVLPPrice() public view returns (uint256) {
        return IVault(velaMintBurnVault).getVLPPrice();
    }

    function computesAmountToBeSoldInVLPUpdateShareAndDebtRatio(
        uint256 withdrawableAmount,
        uint256 id,
        address sender
    ) internal returns (uint256) {
        uint256 updatedDebt;
        uint256 value;
        // when new value is 0, then it shows the SAKE vault is been created, get the current debt and value
        // else get the previous debt and value
        (updatedDebt, value, ) = updateDebtAndValueAmount(id, true);
        // get the difference between the current value and the updated debt
        // use the difference to and the withdrawable amount * value / difference.
        uint256 subDebtFromValue = value - updatedDebt;
        uint256 withdrawableAmountMulValue = withdrawableAmount.mulDiv(value, subDebtFromValue);
        // the previous debt and value is used to calculate the shares, using the withdrawable amount.
        (uint256 previousValue, uint256 previousDebt) = storeDebtRatio(id, withdrawableAmountMulValue);
        _updateShares(id, sender, withdrawableAmount, previousValue, previousDebt);
        // the amount of VLP to be sold is the withdrawable amount / the current VLP price
        uint256 requireAMountOfVLPToBeSold = withdrawableAmountMulValue.mulDiv(10 ** 18, getVLPPrice() * 10);
        // // update the total amount of VLP in the SAKE vault
        sakeVaultInfo[id].totalAmountOfVLP -= requireAMountOfVLPToBeSold;
        // // return the amount of VLP to be sold
        return requireAMountOfVLPToBeSold;
    }

    function initializedAllSakeUsersShares(uint256 id) private {
        uint256 totalUsers = sakeVaultInfo[id].users.length;
        uint256 amountWithoutLeverage = sakeVaultInfo[id].totalAmountOfUSDCWithoutLeverage;
        for (uint256 i = 0; i < totalUsers; ) {
            address user = sakeVaultInfo[id].users[i];
            uint256 _amountDepositedAndLeverage = userDepositInfo[user][id].amount;
            userDepositInfo[user][id].shares = (
                _amountDepositedAndLeverage.mulDiv(RATE_PRECISION, amountWithoutLeverage)
            );
            unchecked {
                i++;
            }
        }
    }

    function storeDebtRatio(
        uint256 id,
        uint256 requireToBeSold
    ) private returns (uint256 previousValue, uint256 previousDebt) {
        uint256 updatedDebt;
        uint256 value;
        uint256 dvtRatio;

        previousValue = updatedDebtRatio[id].newValue;
        previousDebt = updatedDebtRatio[id].newDebt;
        if (requireToBeSold == 0) {
            (updatedDebt, value, dvtRatio) = updateDebtAndValueAmount(id, true);
        } else {
            (updatedDebt, value, dvtRatio) = updateDebtAndValueAmount(id, false);
            value = value - requireToBeSold;
            updatedDebt = value.mulDiv(dvtRatio, RATE_PRECISION);
        }
        updatedDebtRatio[id].newDebt = updatedDebt;
        updatedDebtRatio[id].newValue = value;
        updatedDebtRatio[id].newRatio = dvtRatio;
    }

    function _updateShares(
        uint256 id,
        address sender,
        uint256 withdrawableAmount,
        uint256 previousValue,
        uint256 previousDebt
    ) private {
        uint256 newDebt = updatedDebtRatio[id].newDebt;
        uint256 newValue = updatedDebtRatio[id].newValue;
        // get the total number of users in the SAKE vault
        uint256 totalUsers = sakeVaultInfo[id].users.length;
        for (uint256 i = 0; i < totalUsers; ) {
            // load the user address into memory
            address user = sakeVaultInfo[id].users[i];
            if (user == sender) {
                uint256 subAmountFromMaxWithdrawal = beforeWithdrawal(id, previousValue, previousDebt, user) -
                    withdrawableAmount;

                uint256 _newShare = subAmountFromMaxWithdrawal.mulDiv(RATE_PRECISION, (newValue - newDebt));
                userDepositInfo[sender][id].shares = _newShare;
                userDepositInfo[sender][id].totalWithdrawn = subAmountFromMaxWithdrawal;
            } else {
                uint256 subAmountFromMaxWithdrawal = beforeWithdrawal(id, previousValue, previousDebt, user);

                uint256 share = subAmountFromMaxWithdrawal.mulDiv(RATE_PRECISION, ((newValue - newDebt)));
                userDepositInfo[user][id].shares = share;
            }
            unchecked {
                i++;
            }
        }
    }

    function updateDebtAndValueAmount(
        uint256 id,
        bool state
    ) public returns (uint256 newDebt, uint256 Value, uint256 dvtRatio) {
        // convert total amount of VLP to USDC
        uint256 amountInUSDC = convertVLPToUSDC(sakeVaultInfo[id].totalAmountOfVLP);

        uint256 profitDifferences;

        // profit difference should be with previous value
        uint256 getPreviousValue = updatedDebtRatio[id].newValue;
        // check if there is profit
        // i.e the total amount of VLP in USDC is greater than the current amount with leverage
        // and when there is not profit the debt remains.
        if (amountInUSDC > getPreviousValue) {
            profitDifferences = amountInUSDC - getPreviousValue;
        }
        // calculate the fee split rateand reward split to water when there is profit
        (uint256 feeSplit, ) = calculateFeeSplitRate();
        // rewardSplitToWater returns 0 when there is no profit

        uint256 rewardSplitToWater = (profitDifferences.mulDiv(feeSplit, RATE_PRECISION));
        uint256 previousDebt = updatedDebtRatio[id].newDebt;
        uint256 previousDebtAddRewardSplit = previousDebt + rewardSplitToWater;
        uint256 totalDebt;
        if (state) {
            if (previousDebt == 0) {
                totalDebt = (sakeVaultInfo[id].totalAmountOfUSDCWithoutLeverage * 2);
            } else {
                totalDebt = previousDebtAddRewardSplit;
                IWater(water).updateTotalDebt(rewardSplitToWater);
            }
        }
        if (!state) {
            uint256 getPreviousDVTRatio = previousDebtAddRewardSplit.mulDiv(RATE_PRECISION, amountInUSDC);
            totalDebt = amountInUSDC.mulDiv(getPreviousDVTRatio, RATE_PRECISION);
        }

        updatedDebtRatio[id].newDebt = totalDebt;
        updatedDebtRatio[id].newValue = amountInUSDC;
        updatedDebtRatio[id].newRatio = totalDebt.mulDiv(RATE_PRECISION, amountInUSDC);
        // new debt is the total amount of USDC without leverage * 2 + rewardSplitToWater
        // DVT Ratio is the total amount of new debt / total amount of VLP in USDC
        // uint256 calculateDVTRatio = totalDebt.mulDiv(RATE_PRECISION, amountInUSDC);
        // return the new debt, amount in USDC which is the total amount of VLP in USDC and the DVT Ratio
        return (totalDebt, amountInUSDC, totalDebt.mulDiv(RATE_PRECISION, amountInUSDC));
    }

    //change to public for testing purpose
    function calculateFeeSplitRate() public view returns (uint256 feeSplitRate, uint256 utilizationRatio) {
        (, bytes memory result) = address(water).staticcall(abi.encodeWithSignature("totalAssets()"));
        uint256 totalUSDCInWaterVault = abi.decode(result, (uint256));

        uint256 totalDebt = IWater(water).getTotalDebt();
        (feeSplitRate, utilizationRatio) = feeSplitStrategy.calculateFeeSplit(
            (totalUSDCInWaterVault - totalDebt),
            totalDebt
        );
        return (feeSplitRate, utilizationRatio);
    }

    function beforeWithdrawal(
        uint256 id,
        uint256 previousValue,
        uint256 previousDebt,
        address user
    ) public view returns (uint256 max) {
        // convert total amount of VLP to USDC
        uint256 amountInUSDC = convertVLPToUSDC(sakeVaultInfo[id].totalAmountOfVLP);
        uint256 profitDifferences;
        // profit difference should be with previous value
        // uint256 getPreviousValue = updatedDebtRatio[id].newValue;
        // check if there is profit
        // i.e the total amount of VLP in USDC is greater than the current amount with leverage
        // and when there is not profit the debt remains.
        if (amountInUSDC > previousValue) {
            profitDifferences = amountInUSDC - previousValue;
        }
        // calculate the fee split rateand reward split to water when there is profit
        (uint256 feeSplit, ) = calculateFeeSplitRate();
        // rewardSplitToWater returns 0 when there is no profit
        uint256 rewardSplitToWater = (profitDifferences.mulDiv(feeSplit, RATE_PRECISION));
        // uint256 previousDebt = updatedDebtRatio[id].newDebt;
        uint256 previousDebtAddRewardSplit = previousDebt + rewardSplitToWater;
        uint256 currentShares = userDepositInfo[user][id].shares;

        uint256 _max = (amountInUSDC - previousDebtAddRewardSplit).mulDiv(currentShares, RATE_PRECISION);

        return (_max);
    }

    /* ##################################################################
                                VIEW FUNCTIONS
    ################################################################## */

    function maxWithdraw(uint256 id, uint256 currentShares) public returns (uint256) {
        uint256 updatedDebt;
        uint256 value;
        if (updatedDebtRatio[id].newValue != 0) {
            (updatedDebt, value, ) = updateDebtAndValueAmount(id, true);
        } else {
            updatedDebt = updatedDebtRatio[id].newDebt;
            value = updatedDebtRatio[id].newValue;
        }
        uint256 currentShareDivRate = (value - updatedDebt).mulDiv(currentShares, RATE_PRECISION);
        return currentShareDivRate;
    }

    // preview withdrawal
    function previewWithdraw(uint256 id, address user) public returns (uint256) {
        uint256 shares;
        // uint256 _currentID = updatedDebtRatio[id].newValue == 0
        //     ? _currentId
        //     : updatedDebtRatio[id].newValue;
        if (updatedDebtRatio[id].newValue == 0) {
            uint256 _totalAmount = sakeVaultInfo[id].totalAmountOfUSDCWithoutLeverage * 3;
            shares = ((userDepositInfo[user][id].amount * 3).mulDiv(RATE_PRECISION, _totalAmount));
        } else {
            shares = userDepositInfo[user][id].shares;
        }
        return maxWithdraw(id, shares);
    }

    /** @dev See {IBartender-getFeeStatus}. */
    function getFeeStatus() external view returns (address, bool, uint96) {
        return (feeRecipient, feeEnabled, feeBPS);
    }

    /** @dev See {IBartender-getCurrentId}. */
    function getCurrentId() external view returns (uint256) {
        return _currentId;
    }

    /** @dev See {IBartender-getKeeper}. */
    function getKeeper() external view returns (address) {
        return keeper;
    }

    function getSakeVLPBalance(uint256 id) external view returns (uint256) {
        address sake = sakeVault[id];
        return Sake(sake).getSakeBalanceInVLP();
    }

    function getSakeVaultInfo(uint256 id) external view returns (SakeVaultInfo memory) {
        return sakeVaultInfo[id];
    }

    function depositInfo(uint256 id, address user) external view returns (UserDepositInfo memory) {
        return userDepositInfo[user][id];
    }

    function getDebtInfo(uint256 id) external view returns (UpdatedDebtRatio memory debtInfo) {
        return updatedDebtRatio[id];
    }

    function getSakeAddress(uint256 id) public view returns (address sake) {
        return sakeVault[id];
    }

    function getClaimable(uint256 id) public view returns (uint256) {
        return Sake(sakeVault[id]).getClaimable();
    }

    function withdrawVesting(uint256 id) public onlyOwner {
        Sake(sakeVault[id]).withdrawVesting();
    }

    function setLiquidated(uint256 id) public onlyLiquor returns (address sakeAddress) {
        sakeVaultInfo[id].isLiquidated = true;
        return sakeVault[id];
    }
}

