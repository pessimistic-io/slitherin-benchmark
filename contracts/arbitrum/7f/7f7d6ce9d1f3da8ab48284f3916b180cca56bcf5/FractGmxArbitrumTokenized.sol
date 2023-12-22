// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import { IGlpManager } from "./IGlpManager.sol";
import { IRewardRouter } from "./IRewardRouter.sol";
import { IVester } from "./IVester.sol";
import "./FractBaseTokenizedStrategy.sol";

contract FractGmxArbitrumTokenized is FractBaseTokenizedStrategy {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                        Constants and Immutables
    //////////////////////////////////////////////////////////////*/

    //gmx vault
    address constant GMX_VAULT = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
    //reward router
    address constant REWARD_ROUTER = 0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1;
    //glp manager
    address constant GLP_MANAGER = 0x3963FfC9dff443c2A94f21b129D429891E32ec18;
    //proxy router
    address constant REWARD_ROUTER_V2 = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;
    //glp vester
    address constant GLP_VESTER = 0xA75287d2f8b217273E7FCD7E86eF07D33972042E;
    //glp token
    address constant GLP = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
    //fs glp token
    address constant FS_GLP = 0x1aDDD80E6039594eE970E5872D247bf0414C8903;
    //esgmx
    address constant ESGMX = 0xf42Ae1D54fd613C9bb14810b0588FaAa09a426cA;

    /*///////////////////////////////////////////////////////////////
                        Constructor
    //////////////////////////////////////////////////////////////*/
    /**
     * @dev Initializes the contract setting the deployer as the operator.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) FractBaseTokenizedStrategy(_name, _symbol, _decimals){}

    /*///////////////////////////////////////////////////////////////
                            Base Operations
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Deposit into the strategy.
     * @param token token to deposit.
     * @param amount amount of tokens to deposit.
     */

    function deposit(IERC20 token, uint256 amount) external onlyOwner
    {
        _deposit(token, amount);
    }

    /**
     * @notice Withdraw from the strategy. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function withdraw(IERC20 token, uint256 amount) external onlyOwner 
    {
        _withdraw(token, amount);
    }

    /**
     * @notice Withdraw from the strategy to the owner. 
     * @param token token to withdraw.
     * @param amount amount of tokens to withdraw.
     */
    function withdrawToOwner(IERC20 token, uint256 amount) external onlyOperator 
    {
        _withdrawToOwner(token, amount);
    }

    /**
     * @notice Swap rewards via the paraswap router.
     * @param token The token to swap.
     * @param amount The amount of tokens to swap. 
     * @param callData The callData to pass to the paraswap router. Generated offchain.
     */
    function swap(IERC20 token, uint256 amount, bytes memory callData) external payable onlyOperator 
    {
        //call internal swap
        _swap(token, amount, callData);
    }
    
    /*///////////////////////////////////////////////////////////////
                            Strategy Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Enter into a position
     * @param token The token to enter a position with.
     * @param amount The amount to enter a position with.
     * @param minAmount The minimum amount expected back after entering a position.
     */
    function enterPosition(IERC20 token, uint256 amount, uint256 minAmount) external onlyOwnerOrOperator
    {
        require(amount > 0, '0 Amount');
        token.safeApprove(REWARD_ROUTER_V2, amount);
        token.safeApprove(GLP_MANAGER, amount);

        //check balance before
        uint256 fsGlpBalanceBefore = IERC20(FS_GLP).balanceOf(address(this));
    
        IRewardRouter(REWARD_ROUTER_V2).mintAndStakeGlp(address(token), amount, 0, minAmount);

        //check balance after
        uint256 fsGlpBalanceAfter = IERC20(FS_GLP).balanceOf(address(this));

        //verify mint
        require(fsGlpBalanceAfter >= fsGlpBalanceBefore, 'mint failed');

        token.safeApprove(REWARD_ROUTER_V2, 0);
        token.safeApprove(GLP_MANAGER, 0);
    }

    /**
     * @notice Exit a position
     * @param token The token to exit a position with.
     * @param amount The amount to burn or exit a position with.
     * @param minAmount The minimum amount expected back after exiting.
     */
    function exitPosition(IERC20 token, uint256 amount, uint256 minAmount) external onlyOwnerOrOperator
    {

        require(amount > 0, '0 Amount');

        //check balance before
        uint256 tokenBalanceBefore = token.balanceOf(address(this));

        IRewardRouter(REWARD_ROUTER_V2).unstakeAndRedeemGlp(address(token), amount, minAmount, address(this));

        //check balance after
        uint256 tokenBalanceAfter = token.balanceOf(address(this));

        //verify
        require(tokenBalanceAfter >= tokenBalanceBefore, 'burn failed');

    }

    /**
     * @notice Deposit esGMX. 
     */
    function depositEsGmx() external onlyOperator
    {
        uint256 esGmxBalance = IERC20(ESGMX).balanceOf(address(this));

        require(IERC20(ESGMX).approve(GLP_VESTER, esGmxBalance), 'approve failed');

        IVester(GLP_VESTER).deposit(esGmxBalance);

    }

    /**
     * @notice Withdraw esGMX. 
     */
    function withdrawEsGmx() external onlyOperator
    {
       IVester(GLP_VESTER).withdraw();
    }

    /**
     * @notice Claim pending rewards.
     */
    function claimRewards() external onlyOperator
    {
        IRewardRouter(REWARD_ROUTER).handleRewards(
            true,
            false,
            true,
            false,
            false,
            true,
            false
        );
    }
    /*///////////////////////////////////////////////////////////////
                        Getters
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current price of GLP.
     */ 
    function getCurrentGlpPrice() external view returns (uint256) 
    {
        uint256 currentGlpPrice = IGlpManager(GLP_MANAGER).getAumInUsdg(true) * ONE_ETHER / IERC20(GLP).totalSupply();

        return currentGlpPrice;
    }

}
