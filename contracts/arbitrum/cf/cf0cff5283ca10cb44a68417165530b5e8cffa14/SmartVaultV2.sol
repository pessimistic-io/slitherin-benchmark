// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IEUROs.sol";
import "./IPriceCalculator.sol";
import "./ISmartVault.sol";
import "./ISmartVaultManager.sol";
import "./ISmartVaultManagerV2.sol";
import "./ISwapRouter.sol";
import "./ITokenManager.sol";
import "./IWETH.sol";

contract SmartVaultV2 is ISmartVault {
    using SafeERC20 for IERC20;

    string private constant INVALID_USER = "err-invalid-user";
    string private constant UNDER_COLL = "err-under-coll";
    uint8 private constant version = 2;
    bytes32 private constant vaultType = bytes32("EUROs");
    bytes32 private immutable NATIVE;
    address public immutable manager;
    IEUROs public immutable EUROs;
    IPriceCalculator public immutable calculator;

    address public owner;
    uint256 private minted;
    bool private liquidated;

    event CollateralRemoved(bytes32 symbol, uint256 amount, address to);
    event AssetRemoved(address token, uint256 amount, address to);
    event EUROsMinted(address to, uint256 amount, uint256 fee);
    event EUROsBurned(uint256 amount, uint256 fee);

    constructor(bytes32 _native, address _manager, address _owner, address _euros, address _priceCalculator) {
        NATIVE = _native;
        owner = _owner;
        manager = _manager;
        EUROs = IEUROs(_euros);
        calculator = IPriceCalculator(_priceCalculator);
    }

    modifier onlyVaultManager {
        require(msg.sender == manager, INVALID_USER);
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner, INVALID_USER);
        _;
    }

    modifier ifMinted(uint256 _amount) {
        require(minted >= _amount, "err-insuff-minted");
        _;
    }

    modifier ifNotLiquidated {
        require(!liquidated, "err-liquidated");
        _;
    }

    function getTokenManager() private view returns (ITokenManager) {
        return ITokenManager(ISmartVaultManager(manager).tokenManager());
    }

    function euroCollateral() private view returns (uint256 euros) {
        ITokenManager tokenManager = ITokenManager(ISmartVaultManager(manager).tokenManager());
        ITokenManager.Token[] memory acceptedTokens = tokenManager.getAcceptedTokens();
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            ITokenManager.Token memory token = acceptedTokens[i];
            euros += calculator.tokenToEur(token, getAssetBalance(token.symbol, token.addr));
        }
    }

    function maxMintable() private view returns (uint256) {
        return euroCollateral() * ISmartVaultManager(manager).HUNDRED_PC() / ISmartVaultManager(manager).collateralRate();
    }

    function getAssetBalance(bytes32 _symbol, address _tokenAddress) private view returns (uint256 amount) {
        return _symbol == NATIVE ? address(this).balance : IERC20(_tokenAddress).balanceOf(address(this));
    }

    function getAssets() private view returns (Asset[] memory) {
        ITokenManager tokenManager = ITokenManager(ISmartVaultManager(manager).tokenManager());
        ITokenManager.Token[] memory acceptedTokens = tokenManager.getAcceptedTokens();
        Asset[] memory assets = new Asset[](acceptedTokens.length);
        for (uint256 i = 0; i < acceptedTokens.length; i++) {
            ITokenManager.Token memory token = acceptedTokens[i];
            uint256 assetBalance = getAssetBalance(token.symbol, token.addr);
            assets[i] = Asset(token, assetBalance, calculator.tokenToEur(token, assetBalance));
        }
        return assets;
    }

    function status() external view returns (Status memory) {
        return Status(
            address(this), minted, maxMintable(), euroCollateral(), getAssets(),
            liquidated, version, vaultType
        );
    }

    function undercollateralised() public view returns (bool) {
        return minted > maxMintable();
    }

    function liquidateNative() private {
        if (address(this).balance != 0) {
            (bool sent,) = payable(ISmartVaultManager(manager).protocol()).call{value: address(this).balance}("");
            require(sent, "err-native-liquidate");
        }
    }

    function liquidateERC20(IERC20 _token) private {
        if (_token.balanceOf(address(this)) != 0) _token.safeTransfer(ISmartVaultManager(manager).protocol(), _token.balanceOf(address(this)));
    }

    function liquidate() external onlyVaultManager {
        require(undercollateralised(), "err-not-liquidatable");
        liquidated = true;
        minted = 0;
        liquidateNative();
        ITokenManager.Token[] memory tokens = ITokenManager(ISmartVaultManager(manager).tokenManager()).getAcceptedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].symbol != NATIVE) liquidateERC20(IERC20(tokens[i].addr));
        }
    }

    receive() external payable {}

    function canRemoveCollateral(ITokenManager.Token memory _token, uint256 _amount) private view returns (bool) {
        if (minted == 0) return true;
        uint256 currentMintable = maxMintable();
        uint256 eurValueToRemove = calculator.tokenToEur(_token, _amount);
        return currentMintable >= eurValueToRemove &&
            minted <= currentMintable - eurValueToRemove;
    }

    function removeCollateralNative(uint256 _amount, address payable _to) external onlyOwner {
        require(canRemoveCollateral(getTokenManager().getToken(NATIVE), _amount), UNDER_COLL);
        (bool sent,) = _to.call{value: _amount}("");
        require(sent, "err-native-call");
        emit CollateralRemoved(NATIVE, _amount, _to);
    }

    function removeCollateral(bytes32 _symbol, uint256 _amount, address _to) external onlyOwner {
        ITokenManager.Token memory token = getTokenManager().getToken(_symbol);
        require(canRemoveCollateral(token, _amount), UNDER_COLL);
        IERC20(token.addr).safeTransfer(_to, _amount);
        emit CollateralRemoved(_symbol, _amount, _to);
    }

    function removeAsset(address _tokenAddr, uint256 _amount, address _to) external onlyOwner {
        ITokenManager.Token memory token = getTokenManager().getTokenIfExists(_tokenAddr);
        if (token.addr == _tokenAddr) require(canRemoveCollateral(token, _amount), UNDER_COLL);
        IERC20(_tokenAddr).safeTransfer(_to, _amount);
        emit AssetRemoved(_tokenAddr, _amount, _to);
    }

    function fullyCollateralised(uint256 _amount) private view returns (bool) {
        return minted + _amount <= maxMintable();
    }

    function mint(address _to, uint256 _amount) external onlyOwner ifNotLiquidated {
        uint256 fee = _amount * ISmartVaultManager(manager).mintFeeRate() / ISmartVaultManager(manager).HUNDRED_PC();
        require(fullyCollateralised(_amount + fee), UNDER_COLL);
        minted = minted + _amount + fee;
        EUROs.mint(_to, _amount);
        EUROs.mint(ISmartVaultManager(manager).protocol(), fee);
        emit EUROsMinted(_to, _amount, fee);
    }

    function burn(uint256 _amount) external ifMinted(_amount) {
        uint256 fee = _amount * ISmartVaultManager(manager).burnFeeRate() / ISmartVaultManager(manager).HUNDRED_PC();
        minted = minted - _amount;
        EUROs.burn(msg.sender, _amount);
        IERC20(address(EUROs)).safeTransferFrom(msg.sender, ISmartVaultManager(manager).protocol(), fee);
        emit EUROsBurned(_amount, fee);
    }

    function getSwapAddressFor(bytes32 _symbol) private view returns (address swapAddress) {
        bool validToken;
        ITokenManager.Token[] memory tokens = ITokenManager(ISmartVaultManager(manager).tokenManager()).getAcceptedTokens();
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i].symbol == _symbol) {
                validToken = true;
                swapAddress = tokens[i].addr;
            }
        }
        require(validToken, "err-invalid-swap");
        if (swapAddress == address(0)) swapAddress = ISmartVaultManagerV2(manager).weth();
    }

    function executeNativeSwapAndFee(ISwapRouter.ExactInputSingleParams memory _params, uint256 _swapFee) private {
        (bool sent,) = payable(ISmartVaultManager(manager).protocol()).call{value: _swapFee}("");
        require(sent, "err-swap-fee-native");
        ISwapRouter(ISmartVaultManagerV2(manager).swapRouter()).exactInputSingle{value: _params.amountIn}(_params);
    }

    function executeERC20SwapAndFee(ISwapRouter.ExactInputSingleParams memory _params, uint256 _swapFee) private {
        IERC20(_params.tokenIn).safeTransfer(ISmartVaultManager(manager).protocol(), _swapFee);
        IERC20(_params.tokenIn).safeApprove(ISmartVaultManagerV2(manager).swapRouter(), _params.amountIn);
        ISwapRouter(ISmartVaultManagerV2(manager).swapRouter()).exactInputSingle(_params);
        IWETH weth = IWETH(ISmartVaultManagerV2(manager).weth());
        // convert potentially received weth to eth
        uint256 wethBalance = weth.balanceOf(address(this));
        if (wethBalance > 0) weth.withdraw(wethBalance);
    }

    function swap(bytes32 _inToken, bytes32 _outToken, uint256 _amount) external onlyOwner {
        uint256 swapFee = _amount * ISmartVaultManagerV2(manager).swapFeeRate() / ISmartVaultManager(manager).HUNDRED_PC();
        address inToken = getSwapAddressFor(_inToken);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: inToken,
                tokenOut: getSwapAddressFor(_outToken),
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _amount - swapFee,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        inToken == ISmartVaultManagerV2(manager).weth() ?
            executeNativeSwapAndFee(params, swapFee) :
            executeERC20SwapAndFee(params, swapFee);
    }

    function setOwner(address _newOwner) external onlyVaultManager {
        owner = _newOwner;
    }
}

