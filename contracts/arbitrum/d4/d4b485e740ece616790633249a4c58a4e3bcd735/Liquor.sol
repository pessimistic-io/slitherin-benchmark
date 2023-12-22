//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;
import "./console.sol";
import {IBartender, IERC20, UserDepositInfo, SakeVaultInfo, UpdatedDebtRatio} from "./IBartender.sol";
import {Constant} from "./Constant.sol";
import {Sake} from "./Sake.sol";
import {IWater} from "./IWater.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Math} from "./Math.sol";

error NotAKeeper();
error ThrowInvalidAmount();
error ThrowLiquidationThresholdHasNotReached();

contract Liquor is Ownable, Constant {
    using Math for uint256;

    event Liquidate(
        uint256 SakeVaultId,
        address SakeVaultAddress,
        uint256 AmountToSakeUsers,
        uint256 amountToSafe,
        uint256 outstandingAmountToWater
    );
    IBartender public bartender;
    IWater public water;
    IERC20 public usdcToken;
    address public keeper;

    mapping(address => mapping(uint256 => uint256)) public withdrawableAmount;

    constructor(address _usdcToken, address _water, address _keeper) {
        usdcToken = IERC20(_usdcToken);
        water = IWater(_water);
        keeper = _keeper;
    }

    function setBartender(address _bartender) external onlyOwner {
        bartender = IBartender(_bartender);
    }

    function setKeeper(address _keeper) external onlyOwner {
        keeper = _keeper;
    }

    modifier onlyKeeper() {
        if (keeper != msg.sender) revert NotAKeeper();
        _;
    }

    function liquidateSakeVault(
        uint256 _id
    ) public onlyKeeper returns (uint256 AmountToSakeUsers, uint256 amountToSafe, uint256 outstandingAmountToWater) {
        //@note disabled the check since bartender is not emitting the correct DVT ratio
        //
        if (bartender.getDebtInfo(_id).newRatio < (90 * RATE_PRECISION) / 100) {
            revert ThrowLiquidationThresholdHasNotReached();
        }
        UpdatedDebtRatio memory debtInfo = getDebtinfo(_id);
        SakeVaultInfo memory sakeInfo = bartender.getSakeVaultInfo(_id);
        Sake sake = Sake(bartender.getSakeAddress(_id));
        // sell all VLP for the sub sake
        (, uint256 usdcAmount) = sake.withdraw(address(this), sakeInfo.totalAmountOfVLP);
        bartender.setLiquidated(_id);
        usdcToken.approve(address(water), usdcAmount);

        //if liquidation > debt:
        // repay all the debt, record the remaining balance;
        // check the debt balance of the sub-sake;
        if (usdcAmount >= debtInfo.newDebt) {
            water.repayDebt(debtInfo.newDebt);
            amountToSafe = (usdcToken.balanceOf(address(this)) / 2);
            usdcToken.transfer(keeper, amountToSafe);
            AmountToSakeUsers = (usdcToken.balanceOf(address(this)));

            uint256 length = sakeInfo.users.length;
            for (uint256 i; i < length; ) {
                address sakeUser = sakeInfo.users[i];
                uint256 userShares = getUserShares(_id, sakeUser);
                recordLiquidatedValue(_id, sakeUser, userShares, AmountToSakeUsers);

                {
                    unchecked {
                        i++;
                    }
                }
            }
            //@todo clean up all the states in userDepositInfo and SakeInfo, or add a boolean to disable all withdrawal
            //@todo may change to a safe instead of the keeper;

            emit Liquidate(_id, bartender.getSakeAddress(_id), AmountToSakeUsers, amountToSafe, 0);

            return (AmountToSakeUsers, amountToSafe, 0);
        } else {
            //if liquidation < debt;
            // pay the debt, safe transfer additional amount;
            water.repayDebt(usdcAmount);
            outstandingAmountToWater = debtInfo.newDebt - usdcAmount;
            //@todo Safe should deposit the outstandingAmount to water vault directly.
            return (0, 0, outstandingAmountToWater);
        }
    }

    function getDebtinfo(uint256 _id) public view returns (UpdatedDebtRatio memory debtInfo) {
        return bartender.getDebtInfo(_id);
    }

    function getDTVRatio(uint256 _id) public view returns (uint256 dtvRatio) {
        return bartender.getDebtInfo(_id).newRatio;
    }

    function getSakeUsers(uint256 _id) public view returns (address[] memory) {
        SakeVaultInfo memory sakeInfo = bartender.getSakeVaultInfo(_id);

        return sakeInfo.users;
    }

    function getUserShares(uint256 _id, address _user) public view returns (uint256 shares) {
        UserDepositInfo memory userInfo = bartender.depositInfo(_id, _user);

        return userInfo.shares;
    }

    function recordLiquidatedValue(uint256 _id, address _user, uint256 shares, uint256 totalAmount) internal {
        uint256 _amount = shares.mulDiv(totalAmount, RATE_PRECISION);

        withdrawableAmount[_user][_id] = _amount;

        // usdcToken.transfer(_user, _amount);
    }

    //user withdrawal on liquidation
    function withdraw(uint256 _id) public returns (uint256 wihtdrawnAmount) {
        uint256 amount = withdrawableAmount[msg.sender][_id];
        if (amount <= 0) {
            revert ThrowInvalidAmount();
        } else {
            (address feeRecipient, bool feeEnabled, uint96 feeBPS) = getFeeStatus();
            if (!feeEnabled) {
                usdcToken.transfer(msg.sender, amount);
            } else {
                uint256 fee = amount.mulDiv(feeBPS, MAX_BPS);
                amount -= fee;
                withdrawableAmount[msg.sender][_id] = 0;
                usdcToken.transfer(feeRecipient, fee);
                usdcToken.transfer(msg.sender, amount);
            }
        }
        return amount;
    }

    function getAmountAfterLiquidation(uint256 _id, address user) public view returns (uint256) {
        return withdrawableAmount[user][_id];
    }

    function getFeeStatus() public view returns (address feeRecipient, bool feeEnabled, uint96 feeBps) {
        return bartender.getFeeStatus();
    }
}

