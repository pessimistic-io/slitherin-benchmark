// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;
pragma abicoder v2;

/*
 Optimization 100000
*/

import "./SwapHelper.sol";
import "./LiquidityHelper.sol";
import "./VaultStructInfo.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./IERC721Receiver.sol";
import "./IV3SwapRouter.sol";

contract Vault is IERC721Receiver, Ownable, ReentrancyGuard {
    using LiquidityHelper for LiquidityHelper.PositionMap;
    using VaultStructInfo for VaultStructInfo.BasicInfo;
    using VaultStructInfo for VaultStructInfo.TradingInfo;
    using VaultStructInfo for VaultStructInfo.TokenAllowedInfo;
    using VaultStructInfo for VaultStructInfo.UniInfo;

    LiquidityHelper.PositionMap private positionMap;
    VaultStructInfo.BasicInfo private basicInfo;
    VaultStructInfo.TradingInfo private tradingInfo;
    VaultStructInfo.TokenAllowedInfo private tokenAllowedInfo;
    VaultStructInfo.UniInfo private uniInfo;
    VaultStructInfo.ApproveInfo private approveInfo;
    mapping(uint256 => VaultStructInfo.LpRemoveRecord) private tokenIdLpInfoMap;

    function initialize(string memory _vaultName, address _dispatcher, address[] memory allowTokens) external onlyOwner {
        basicInfo.initBasicInfo(_vaultName, _dispatcher, 0x5E5994990F3D1Dd989DdCF47F5b4a0eAff905ca6);
        tradingInfo.initTradingInfo();
        uniInfo.initUniInfo();
        tokenAllowedInfo.initTokenAllowedInfo(allowTokens);
    }

    function getVaultName() public view returns (string memory) {
        return basicInfo.vaultName;
    }

    function updateVaultName(string memory _newVaultName) external onlyOwner {
        basicInfo.vaultName = _newVaultName;
    }

    function onERC721Received(address /*operator*/, address, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        positionMap.store[tokenId] = LiquidityHelper.Deposit({
            customerId: tokenId,
            token0: address(this),
            token1: address(this)
        });
        positionMap.keys.push(tokenId);
        positionMap.keyExists[tokenId] = true;
        return this.onERC721Received.selector;
    }

    modifier dispatcherCheck() {
        require(basicInfo.dispatcher == msg.sender || owner() == msg.sender, "Permission error: caller is not the dispatcher");
        _;
    }

    modifier onlyDispatcherCheck() {
        require(basicInfo.dispatcher == msg.sender, "Permission error: caller is not the dispatcher");
        _;
    }

    modifier allowListCheck(address tokenAddress) {
        require(tokenAllowedInfo.tokenExists[tokenAddress].allowed, "Token is not in allowlist");
        _;
    }

    function swapInputETHForToken(address tokenOut, uint24 fee, uint256 amountIn, uint256 amountOutMin) external dispatcherCheck allowListCheck(tokenOut) returns (uint256 amountOut) {
        amountOut = SwapHelper.swapInputETHForToken(tokenOut, fee, amountIn, amountOutMin, uniInfo.swapRouter, uniInfo.WETH);
        return tradingInfo.collectTradingFee(amountOut, tradingInfo.swapTradingFeeRate, tokenOut, basicInfo.socMainContract);
    }

    function swapInputForErc20Token(address tokenIn, address tokenOut, uint24 fee, uint256 amountIn, uint256 amountOutMin) external dispatcherCheck allowListCheck(tokenOut) returns (uint256 amountOut) {
        amountOut = SwapHelper.swapInputForErc20Token(tokenIn, tokenOut, fee, amountIn, amountOutMin, uniInfo.swapRouter, approveInfo.swapApproveMap);
        return tradingInfo.collectTradingFee(amountOut, tradingInfo.swapTradingFeeRate, tokenOut, basicInfo.socMainContract);
    }

    function swapInputTokenToETH(address tokenIn, uint24 fee, uint256 amountIn, uint256 amountOutMin) external dispatcherCheck returns (uint256 amountOut) {
        amountOut = SwapHelper.swapInputTokenToETH(tokenIn, fee, amountIn, amountOutMin, uniInfo.swapRouter, uniInfo.WETH, approveInfo.swapApproveMap);
        return tradingInfo.collectTradingFeeForETH(amountOut, tradingInfo.swapTradingFeeRate, basicInfo.socMainContract);
    }

    function mintPosition(LiquidityHelper.CreateLpObject memory createLpObject) external dispatcherCheck allowListCheck(createLpObject.token0) allowListCheck(createLpObject.token1) {
        positionMap.mintNewPosition(createLpObject, uniInfo.nonfungiblePositionManager, approveInfo.liquidityApproveMap);
    }

    function increaseLiquidity(uint256 positionId, uint256 token0Amount, uint256 token1Amount) external dispatcherCheck {
        LiquidityHelper.increaseLiquidityCurrentRange(uniInfo.nonfungiblePositionManager, positionId, token0Amount, token1Amount);
    }

    function getPositionIds() external view returns (uint256[] memory) {
        return positionMap.getAllKeys();
    }

    function getTokenIdByCustomerId(uint256 customerId) public view returns (uint256) {
        return positionMap.getTokenIdByCustomerId(customerId);
    }

    function removeAllPositionById(uint256 positionId) external dispatcherCheck {
        (uint256 amount0, uint256 amount1) = LiquidityHelper.removeAllPositionById(positionId, uniInfo.nonfungiblePositionManager);
        (uint256 amount0Fee, uint256 amount1Fee) = collectAllFeesInner(positionId, amount0, amount1);
        tokenIdLpInfoMap[positionId] = VaultStructInfo.LpRemoveRecord({
            token0: positionMap.store[positionId].token0,
            token1: positionMap.store[positionId].token1,
            token0Amount: amount0,
            token1Amount: amount1,
            token0FeeAmount: amount0Fee,
            token1FeeAmount: amount1Fee
        });
        positionMap.deleteDeposit(positionId);
    }

    function queryRemovedLpInfo(uint256 tokenId) public view returns(VaultStructInfo.LpRemoveRecord memory) {
        return tokenIdLpInfoMap[tokenId];
    }

    function removeLpInfoByTokenIds(uint256[] memory tokenIds) external dispatcherCheck {
        for(uint16 i = 0; i < tokenIds.length; i++) {
            delete tokenIdLpInfoMap[tokenIds[i]];
        }
    }

    function collectAllFees(uint256 positionId) external dispatcherCheck {
        collectAllFeesInner(positionId, 0, 0);
    }

    function collectAllFeesInner(uint256 positionId, uint256 amount0, uint256 amount1) internal returns (uint256 amount0Fee, uint256 amount1Fee) {
        (amount0Fee, amount1Fee) = LiquidityHelper.collectAllFees(positionId, uniInfo.nonfungiblePositionManager);
        tradingInfo.collectTradingFee(amount0Fee - amount0, tradingInfo.lpTradingFeeRate, positionMap.store[positionId].token0, basicInfo.socMainContract);
        tradingInfo.collectTradingFee(amount1Fee - amount1, tradingInfo.lpTradingFeeRate, positionMap.store[positionId].token1, basicInfo.socMainContract);
        return (amount0Fee - amount0, amount1Fee - amount1);
    }

    function burnNFT(uint128 tokenId) external dispatcherCheck {
        LiquidityHelper.burn(tokenId, uniInfo.nonfungiblePositionManager);
        positionMap.deleteDeposit(tokenId);
    }

    function setDispatcher(address _dispatcher) external onlyOwner {
        basicInfo.dispatcher = _dispatcher;
    }

    function getAllowTokenList() public view returns (VaultStructInfo.AllowTokenObj[] memory) {
        return tokenAllowedInfo.allowList;
    }

    function setSwapAllowList(VaultStructInfo.AllowTokenObj[] memory _allowList) external onlyOwner {
        tokenAllowedInfo.setSwapAllowList(_allowList);
    }

    function updateTradingFee(uint8 _tradingFee) external onlyDispatcherCheck {
        tradingInfo.tradingFee = _tradingFee;
    }

    // Receive ETH
    receive() external payable {}

    // Withdraw ERC721 NFT
    function withdrawErc721NFT(uint256 tokenId) external onlyOwner {
        uniInfo.nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);
        positionMap.deleteDeposit(tokenId);
    }

    // Withdraw ERC20 tokens
    function withdrawTokens(address token, uint256 amount) external onlyOwner {
        TransferHelper.safeTransfer(token, msg.sender, amount);
    }

    // Withdraw ETH
    function withdrawETH(uint256 amount) external onlyOwner {
        TransferHelper.safeTransferETH(msg.sender, amount);
    }

    // Deposit to contract
    function deposit(address depositToken, uint256 amount) external onlyOwner {
        TransferHelper.safeTransferFrom(depositToken, msg.sender, address(this), amount);
    }

    // Deposit ETH to contract, and covert to WETH
    function depositEthToWeth() external payable onlyOwner {
        IWETH(uniInfo.WETH).deposit{value: msg.value}();
    }

}
