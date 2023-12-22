// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "./ERC20.sol";
import {AccessControl} from "./AccessControl.sol";
import {Pausable} from "./Pausable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";

contract ManagedTreasury is AccessControl,Pausable,ReentrancyGuard {
    using SafeTransferLib for address;
    using SafeTransferLib for ERC20;

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR");
    address internal constant DEAD_WALLET = 0x000000000000000000000000000000000000dEaD;
    IUniswapV2Router02 public dexRouter;
    ERC20 public managedToken;

    uint256 public maximumTokenToSwap = 10000e18;
    uint256 public maximumEthToSwap = 10000e18;

    error ZeroAmount();
    error ZeroAddress();
    error InvalidAmount();
    error OnlyCaller();

    modifier onlyCaller() {
        if(!(hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(EXECUTOR_ROLE, msg.sender))) {
            revert OnlyCaller();
        }
        _;
    }

    constructor(address _managedToken,address _owner) {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantRole(EXECUTOR_ROLE, _owner);

        _setRoleAdmin(EXECUTOR_ROLE,DEFAULT_ADMIN_ROLE);
        
        managedToken = ERC20(_managedToken);
    }

    receive() external payable {}

    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setDexRouter(address newRouter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(newRouter == address(0)) revert ZeroAddress();

        dexRouter = IUniswapV2Router02(newRouter);
    }

    function setMaxTokenEthSwap(uint256 newMaximumTokenToSwap,uint256 newMaximumEthToSwap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(newMaximumEthToSwap == 0 || newMaximumTokenToSwap == 0) revert ZeroAmount();
        
        maximumTokenToSwap = newMaximumTokenToSwap;
        maximumEthToSwap = newMaximumEthToSwap;
    }

    function setManagedToken(address newManagedToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if(newManagedToken == address(0)) revert ZeroAddress();
        
        managedToken = ERC20(newManagedToken);
    }

    function recoverLeftOverEth(address to,uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        payable(to).transfer(amount);
    }

    function withdrawForMarketing(address to,uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawCoin(to,amount);
    }

    function withdrawForDevelopment(address to,uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        withdrawCoin(to,amount);
    }

    function withdrawCoin(address to,uint256 amount) internal {
        uint256 contractBalance = address(this).balance;
        if(amount > (contractBalance * 50 / 1e2)) revert InvalidAmount();

        payable(to).transfer(amount);
    }

    function recoverLeftOverToken(address token,address to,uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        ERC20(token).safeTransfer(to,amount);
    }

    function airDrop(address[] calldata newholders, uint256[] calldata amounts) external {
        uint256 iterator = 0;
        require(newholders.length == amounts.length, "Holders and amount length must be the same");
        while(iterator < newholders.length){
            managedToken.safeTransfer(newholders[iterator], amounts[iterator] * 10**18);
            iterator += 1;
        }
    }

    function treasuryBuyBack(uint256 amountEth) external onlyCaller nonReentrant returns (uint256 amountToken) {
        if(!(amountEth <= maximumEthToSwap)) revert InvalidAmount();

        return swapEthForTokens(amountEth,address(managedToken));
    }

    function treasuryAddLiquidityEth(uint256 ethAmount,uint256 tokenAmount) external onlyCaller nonReentrant {
        addLiquidity(tokenAmount, ethAmount);
    }

    function treasurySellManagedToken(uint256 tokenAmount) external onlyCaller nonReentrant {
        swapTokensForEth(managedToken,tokenAmount);
    }

    function treasurySellOtherToken(ERC20 otherToken,uint256 tokenAmount) external onlyCaller nonReentrant {
        swapTokensForEth(otherToken,tokenAmount);
    }

    function treasuryBuyOtherToken(uint256 ethAmount,address toAddress) external onlyCaller nonReentrant {
        swapEthForTokens(ethAmount,toAddress);
    }

    function treasuryBuyBackAndBurn(uint256 amountEth) external onlyCaller nonReentrant returns (bool) {
        if(!(amountEth <= maximumEthToSwap)) revert InvalidAmount();

        burnDeadWallet(swapEthForTokens(amountEth,address(managedToken)));
        return true;
    }

    function treasuryBurn(uint256 tokenAmount) external onlyCaller nonReentrant {        
        burnDeadWallet(tokenAmount);
    }

    function burnDeadWallet(uint256 amount) internal {
        managedToken.safeTransfer(DEAD_WALLET,amount);
    }

    function swapEthForTokens(uint256 ethAmount,address toAddress) private returns (uint256 tokenAmount) {
        address[] memory path = new address[](2);
        path[0] = dexRouter.WETH();
        path[1] = toAddress;

        (uint256[] memory amounts) =
            dexRouter.swapExactETHForTokens{value: ethAmount}(0, path, address(this), block.timestamp);

        return amounts[1];
    }

    function swapTokensForEth(ERC20 fromToken,uint256 tokenAmount) private returns (uint256 ethAmount) {
        address[] memory path = new address[](2);
        path[0] = address(fromToken);
        path[1] = dexRouter.WETH();

        uint256 ethBefore = address(this).balance;

        fromToken.safeApprove(address(dexRouter), tokenAmount);
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 0, path, address(this), block.timestamp
        );

        uint256 ethAfter = address(this).balance;
        return ethAfter - ethBefore;
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        managedToken.safeApprove(address(dexRouter), tokenAmount);

        dexRouter.addLiquidityETH{value: ethAmount}(
            address(managedToken), tokenAmount, 0, 0, address(this), block.timestamp
        );
    }
}
