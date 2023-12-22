// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./BaseModule.sol";
import "./ICompoundReward.sol";
import "./ICometV3.sol";
import "./CometMath.sol";

/**
 * @author  Goblin team
 * @title   CompoundV3 abstraction
 * @dev     The CompoundV3 abstraction is reponsible to abstract the logic of all forks of CompoundV3
 * @notice  Upgradability is needed because most CompoundV3 forks are built with Proxy - it's implementation could be updated
 */

contract CompoundV3Module is BaseModule {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev A constant used for calculating shares
    uint256 private constant IOU_DECIMALS = 1e18;

    /// @dev A constant used for the Comp IOU approximation - 1 wei when 18 decimals
    uint256 private constant IOU_APPROX = 5;

    /// @notice The CompoundV3 fork comptroller contract
    address public compRewardor;
    /// @notice The CompoundV3 fork cToken contrat used by the module
    address public cometToken;
    /// @notice The last updated balance of underlying tokens
    uint256 public lastUpdatedBalance;

    error TimestampTooLarge();

    /**
    * @notice  Disable initializing on implementation contract
    **/
    constructor() {
        _disableInitializers();
    }

    /** proxy **/

    /**
     * @notice  Initializes
     * @dev     Should always be called on deployment
     * @param   _smartFarmooor  Goblin bank of the Module
     * @param   _manager  Manager of the Module
     * @param   _baseToken  Asset contract address
     * @param   _executionFee  Execution fee for withdrawals
     * @param   _dex  Dex Router contract address
     * @param   _rewards  Reward contract addresses
     * @param   _cometToken  Compound comet token, lending market address
     * @param   _compReward Compound reward address
     * @param   _name  Name of the Module
     * @param   _wrappedNative  Address of the Wrapped Native token
     */
    function initialize(
        address _smartFarmooor,
        address _manager,
        address _baseToken,
        uint256 _executionFee,
        address _dex,
        address[] memory _rewards,
        address _cometToken,
        address _compReward,
        string memory _name,
        address _wrappedNative
    ) external initializer {
        _initializeBase(_smartFarmooor, _manager, _baseToken, _executionFee, _dex, _rewards, _name, _wrappedNative);
        _setCometToken(_cometToken);
        _setCompRewardor(_compReward);

        lastUpdatedBalance = 0;

        IERC20Upgradeable(baseToken).safeApprove(_cometToken, type(uint256).max);
    }

    /** manager **/

    /**
     * @notice  Deposit baseToken into CompoundV3 fork - provide liquidity
     * @param   amount  Amount of baseToken to be deposited
     */
    function deposit(uint256 amount) external onlyVault {
        require(amount > 0, "CompoundV3: deposit amount cannot be zero");
        IERC20Upgradeable(baseToken).safeTransferFrom(msg.sender, address(this), amount);
        lastUpdatedBalance += amount;
        ICometV3(cometToken).supply(baseToken, amount);
        emit Deposit(baseToken, amount);
    }

    /**
     * @notice  Withdraw baseToken from CompoundV3
     * @dev     Amount gets converted to shares for withdrawal
     * @param   shareFraction Fraction representing user share of Base token to withdraw
     * @param   receiver  Receiver of the funds
     * @return  withdrawnAmount  Amount of baseToken received
     */
    function withdraw(uint256 shareFraction, address receiver)
    external
    payable
    onlyVault
    returns (uint256 withdrawnAmount, uint asyncAmount)
    {
        require(shareFraction > 0, "CompoundV3: amount cannot be zero");
        require(msg.value == 0, "CompoundV3: msg.value must be zero");

        uint256 totalShares = getBalance();
        uint256 sharesAmount = shareFraction * totalShares / IOU_DECIMALS;

        uint256 balanceBefore = IERC20Upgradeable(baseToken).balanceOf(address(this));
        _withdraw(sharesAmount);
        uint256 balanceAfter = IERC20Upgradeable(baseToken).balanceOf(address(this));

        withdrawnAmount = balanceAfter - balanceBefore;

        if (lastUpdatedBalance > withdrawnAmount) {
            lastUpdatedBalance -= withdrawnAmount;
        } else {
            lastUpdatedBalance = 0;
        }

        emit Withdraw(baseToken, withdrawnAmount);
        if (withdrawnAmount > 0) {
            IERC20Upgradeable(baseToken).safeTransfer(receiver, withdrawnAmount);
        }
        return (withdrawnAmount, 0);
    }

    /**
     * @notice  Harvest the rewards from CompoundV3 fork
     * @param   receiver  Receiver of the harvested rewards, in baseToken
     * @return  uint256  Total profit harvested
     */
    function harvest(address receiver)
    external
    onlyVault
    returns (uint256)
    {
        _lpProfit();
        _rewardsProfit();

        uint256 totalProfit = IERC20Upgradeable(baseToken).balanceOf(address(this));
        if (totalProfit != 0) {
            IERC20Upgradeable(baseToken).safeTransfer(receiver, totalProfit);
        }
        emit Harvest(baseToken, totalProfit);
        return totalProfit;
    }

    /**
     * @notice  Return Maximum withdrawal amount from protocol
    */
    function getMaxWithdrawableAmount() public view returns (uint256) {
        (uint totalSupply, uint totalDebt) = _collectCompoundV3Data();
        uint256 availableLiquidity = _getAvailableLiquidity(totalSupply, totalDebt);
        if (availableLiquidity >= getLastUpdatedBalance())
            return getLastUpdatedBalance();
        return availableLiquidity;
    }

    /**
     * @notice  Get current balance on CompoundV3 fork
     * @dev     Returns an amount in baseToken
     * @return  uint256  Amount of baseToken
     */
    function getBalance() public view returns (uint256) {
        return ICometV3(cometToken).balanceOf(address(this));
    }

    /**
     * @notice  Get last updated balance on CompoundV3 fork
     * @dev     Returns an amount in baseToken
     * @return  uint256  Amount of baseToken
     */
    function getLastUpdatedBalance() public view returns (uint256) {
        return lastUpdatedBalance;
    }

    /**
     * @notice  Get execution fee needed to withdraw from CompoundV3 fork
     * @dev     Returns an amount in native token
     * @return  uint256  Amount of native token
     */
    function getExecutionFee(uint256 amount)
    external
    pure
    override
    returns (uint256)
    {
        return 0;
    }

    /** helper **/

    /**
     * @notice  Calculates the profit - the extra baseToken earned on top of aum
     */
    function _lpProfit() private {
        uint256 currentTotalHoldings = ICometV3(cometToken).balanceOf(address(this));

        if (currentTotalHoldings > 0) {
            //Yes comparing Comp IOU with Base token amount but according to them :
            //"Comet balanceOf : Query the current positive base balance of an account or zero"
            if (currentTotalHoldings > lastUpdatedBalance) {
                uint aumDelta = currentTotalHoldings - lastUpdatedBalance;
                _withdraw(aumDelta);
            }
        }
    }

    /**
     * @notice  Collects the rewards tokens earned on CompoundV3 fork
     * @dev     Reward tokens are swapped for baseToken
     */
    function _rewardsProfit() private {
        _claimAllRewards();
        _swapTokenRewardsForBaseToken();
    }

    /**
    * @notice Withdraw baseToken from CompoundV3
    * @dev Compound v3 shares == underlying amount
    * @param amount Amount of baseToken token to withdraw
    */
    function _withdraw(uint256 amount) private {
        ICometV3(cometToken).withdraw(baseToken, amount);
    }

    /**
    * @notice Swaps rewards tokens for baseTokens
    */
    function _swapTokenRewardsForBaseToken() private {
        uint256 rewardBalance = IERC20Upgradeable(rewards[0]).balanceOf(address(this));
        IUniV3Dex(dex).swap(rewardBalance, rewards[0], baseToken, address(this));
    }

    /**
    * @notice Claims all the COMP tokens
    */
    function _claimAllRewards() private {
        ICompoundReward(compRewardor).claim(
            cometToken,
            address(this),
            true);
    }

    /**
    * @notice  Set Compound collateral cToken
    * @param   _cometToken  Address of the cToken contract
    */
    function _setCometToken(address _cometToken) private {
        require(_cometToken != address(0), "CompoundV3: cannot be the zero address");
        cometToken = _cometToken;
    }

    /**
    * @notice  Set Compound reward address
    * @param   _rewardod  Address of the cToken contract
    */
    function _setCompRewardor(address _rewardod) private {
        require(_rewardod != address(0), "CompoundV3: cannot be the zero address");
        compRewardor = _rewardod;
    }

    /**
     * @notice  CompoundV3 lp token
     * @dev     overridden for cToken address which is CompoundV3 lp token
     * @return  cToken address
     */
    function _lpToken() internal override view returns (address) {
        return cometToken;
    }

    /**
    * @notice  Get total token supply and total debt from cToken
    */
    function _collectCompoundV3Data() private view returns (uint256, uint256) {
        uint256 totalSupply = ICometV3(cometToken).totalSupply();
        uint256 totalBorrow = ICometV3(cometToken).totalBorrow();
        return (totalSupply, totalBorrow);
    }

    /**
    * @notice  Get available liquidity on the cToken
    * @dev     Returns 0 when all the liquidity has been borrowed
    */
    function _getAvailableLiquidity(uint totalSupply, uint totalDebt) private pure returns (uint256) {
        if (totalSupply > totalDebt)
            return totalSupply - totalDebt;
        return 0;
    }
}

