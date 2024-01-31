// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Ownable.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./SiloLens.sol";
import "./ISiloFactory.sol";
import "./IPriceProvider.sol";
import "./ISwapper.sol";
import "./ISiloRepository.sol";
import "./IPriceProvidersRepository.sol";
import "./IWrappedNativeToken.sol";
import "./ChainlinkV3PriceProvider.sol";

import "./Ping.sol";
import "./RevertBytes.sol";


/// @notice LiquidationHelper IS NOT PART OF THE PROTOCOL. SILO CREATED THIS TOOL, MOSTLY AS AN EXAMPLE.
/// see https://github.com/silo-finance/liquidation#readme for details how liquidation process should look like
contract LiquidationHelper is IFlashLiquidationReceiver, Ownable {
    using RevertBytes for bytes;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 immutable private _BASE_TX_COST; // solhint-disable-line var-name-mixedcase
    ISiloRepository public immutable SILO_REPOSITORY; // solhint-disable-line var-name-mixedcase
    IPriceProvidersRepository public immutable PRICE_PROVIDERS_REPOSITORY; // solhint-disable-line var-name-mixedcase
    SiloLens public immutable LENS; // solhint-disable-line var-name-mixedcase
    IERC20 public immutable QUOTE_TOKEN; // solhint-disable-line var-name-mixedcase

    ChainlinkV3PriceProvider public immutable CHAINLINK_PRICE_PROVIDER; // solhint-disable-line var-name-mixedcase
    ChainlinkV3PriceProvider public immutable CHAINLINK_PRICE_PROVIDER2; // solhint-disable-line var-name-mixedcase

    mapping(IPriceProvider => ISwapper) public swappers;

    event LiquidationBalance(address user, uint256 quoteAmountFromCollaterals, uint256 quoteLeftAfterRepay);

    error InvalidSiloLens();
    error InvalidSiloRepository();
    error LiquidationNotProfitable(uint256 inTheRed);
    error NotSilo();
    error PriceProviderNotFound();
    error SwapperNotFound();
    error RepayFailed();
    error SwapAmountInFailed();
    error SwapAmountOutFailed();
    error SwappersMustMatchProviders();
    error UsersMustMatchSilos();
    error ApprovalFailed();
    error InvalidChainlinkProviders();

    constructor (
        address _repository,
        address[] memory _chainlinkPriceProviders,
        address _lens,
        IPriceProvider[] memory _priceProvidersWithSwapOption,
        ISwapper[] memory _swappers,
        uint256 _baseCost
    ) {
        if (!Ping.pong(SiloLens(_lens).lensPing)) revert InvalidSiloLens();

        if (!Ping.pong(ISiloRepository(_repository).siloRepositoryPing)) {
            revert InvalidSiloRepository();
        }

        if (_swappers.length != _priceProvidersWithSwapOption.length) {
            revert SwappersMustMatchProviders();
        }

        SILO_REPOSITORY = ISiloRepository(_repository);
        LENS = SiloLens(_lens);

        for (uint256 i = 0; i < _swappers.length; i++) {
            swappers[_priceProvidersWithSwapOption[i]] = _swappers[i];
        }

        PRICE_PROVIDERS_REPOSITORY = ISiloRepository(_repository).priceProvidersRepository();

        if (_chainlinkPriceProviders.length != 2) revert InvalidChainlinkProviders();

        CHAINLINK_PRICE_PROVIDER = ChainlinkV3PriceProvider(_chainlinkPriceProviders[0]);
        CHAINLINK_PRICE_PROVIDER2 = ChainlinkV3PriceProvider(_chainlinkPriceProviders[1]);

        QUOTE_TOKEN = IERC20(PRICE_PROVIDERS_REPOSITORY.quoteToken());
        _BASE_TX_COST = _baseCost;
    }

    receive() external payable {
        // we accept ETH so we can unwrap WETH
    }

    function executeLiquidation(address[] calldata _users, ISilo _silo, address /* _swapper */) external {
        uint256 gasStart = gasleft();
        _silo.flashLiquidate(_users, abi.encode(gasStart));
    }

    function setSwapper(IPriceProvider _oracle, ISwapper _swapper) external onlyOwner {
        swappers[_oracle] = _swapper;
    }

    /// @dev this is working example of how to perform liquidation, this method will be called by Silo
    ///         Keep in mind, that this helper might NOT choose the best swap option.
    ///         For best results (highest earnings) you probably want to implement your own callback and maybe use some
    ///         dex aggregators.
    function siloLiquidationCallback(
        address _user,
        address[] calldata _assets,
        uint256[] calldata _receivedCollaterals,
        uint256[] calldata _shareAmountsToRepaid,
        bytes memory _flashReceiverData
    ) external override {
        (uint256 gasStart) = abi.decode(_flashReceiverData, (uint256));

        uint256 quoteAmountFromCollaterals = _swapAllForQuote(_assets, _receivedCollaterals);
        uint256 quoteSpentOnRepay = _repay(ISilo(msg.sender), _user, _assets, _shareAmountsToRepaid);
        uint256 gasSpent = gasStart - gasleft() - _BASE_TX_COST;

        if (quoteSpentOnRepay + gasSpent > quoteAmountFromCollaterals) {
            revert LiquidationNotProfitable(quoteSpentOnRepay + gasSpent - quoteAmountFromCollaterals);
        }

        uint256 quoteLeftAfterRepay = quoteAmountFromCollaterals - quoteSpentOnRepay;

        // We assume that quoteToken is wrapped native token
        IWrappedNativeToken(address(QUOTE_TOKEN)).withdraw(quoteLeftAfterRepay);

        payable(owner()).sendValue(quoteLeftAfterRepay);

        emit LiquidationBalance(_user, quoteAmountFromCollaterals, quoteLeftAfterRepay);
    }

    function checkSolvency(address[] memory _users, ISilo[] memory _silos) external view returns (bool[] memory) {
        if (_users.length != _silos.length) revert UsersMustMatchSilos();

        bool[] memory solvency = new bool[](_users.length);

        for (uint256 i; i < _users.length; i++) {
            solvency[i] = _silos[i].isSolvent(_users[i]);
        }

        return solvency;
    }

    function checkDebt(address[] memory _users, ISilo[] memory _silos) external view returns (bool[] memory) {
        bool[] memory hasDebt = new bool[](_users.length);

        for (uint256 i; i < _users.length; i++) {
            hasDebt[i] = LENS.inDebt(_silos[i], _users[i]);
        }

        return hasDebt;
    }

    function findPriceProvider(address _asset) public view returns (IPriceProvider) {
        IPriceProvider priceProvider = PRICE_PROVIDERS_REPOSITORY.priceProviders(_asset);

        if (priceProvider == CHAINLINK_PRICE_PROVIDER) {
            priceProvider = CHAINLINK_PRICE_PROVIDER.getFallbackProvider(_asset);
        }

        if (priceProvider == CHAINLINK_PRICE_PROVIDER2) {
            priceProvider = CHAINLINK_PRICE_PROVIDER2.getFallbackProvider(_asset);
        }

        if (address(priceProvider) == address(0)) {
            revert PriceProviderNotFound();
        }

        return priceProvider;
    }

    function _swapAllForQuote(
        address[] calldata _assets,
        uint256[] calldata _receivedCollaterals
    ) internal returns (uint256 quoteAmount) {
        // swap all for quote token

        unchecked {
            // we will not overflow with `i` in a lifetime
            for (uint256 i = 0; i < _assets.length; i++) {
                // if silo was able to handle solvency calculations, then we can handle quoteAmount without safe math
                quoteAmount += _swapForQuote(_assets[i], _receivedCollaterals[i]);
            }
        }
    }

    function _repay(
        ISilo silo,
        address _user,
        address[] calldata _assets,
        uint256[] calldata _shareAmountsToRepaid
    ) internal returns (uint256 quoteSpendOnRepay) {
        if (!SILO_REPOSITORY.isSilo(address(silo))) revert NotSilo();

        for (uint256 i = 0; i < _assets.length; i++) {
            if (_shareAmountsToRepaid[i] == 0) continue;

            // if silo was able to handle solvency calculations, then we can handle amounts without safe math here
            unchecked {
                quoteSpendOnRepay += _swapForAsset(_assets[i], _shareAmountsToRepaid[i]);
            }

            _approve(_assets[i], address(silo), _shareAmountsToRepaid[i]);

            silo.repayFor(_assets[i], _user, _shareAmountsToRepaid[i]);

            // DEFLATIONARY TOKENS ARE NOT SUPPORTED
            // we are not using lower limits for swaps so we may not get enough tokens to do full repay
            // our assumption here is that `_shareAmountsToRepaid[i]` is total amount to repay the full debt
            // if after repay user has no debt in this asset, the swap is acceptable
            if (silo.assetStorage(_assets[i]).debtToken.balanceOf(_user) != 0) {
                revert RepayFailed();
            }
        }
    }

    /// @dev it swaps asset token for quote
    /// @param _asset address
    /// @param _amount exact amount of asset to swap
    /// @return amount of quote token
    function _swapForQuote(address _asset, uint256 _amount) internal returns (uint256) {
        if (_amount == 0 || _asset == address(QUOTE_TOKEN)) return _amount;

        (IPriceProvider provider, ISwapper swapper) = _resolveProviderAndSwapper(_asset);

        bytes memory callData = abi.encodeCall(ISwapper.swapAmountIn, (
            _asset, address(QUOTE_TOKEN), _amount, address(provider), _asset
        ));

        // no need for safe approval, because we always using 100%
        _approve(_asset, swapper.spenderToApprove(), _amount);

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = address(swapper).delegatecall(callData);
        // if (!success) data.revertBytes("SwapAmountInFailed");
        if (!success && data.length > 0) {
            assembly { // solhint-disable-line no-inline-assembly
                revert(add(32, data), mload(data))
            }
        }

        return abi.decode(data, (uint256));
    }

    /// @dev it swaps quote token for asset
    /// @param _asset address
    /// @param _amount exact amount OUT, what we want to receive
    /// @return amount of quote token used for swap
    function _swapForAsset(address _asset, uint256 _amount) internal returns (uint256) {
        if (_amount == 0 || address(QUOTE_TOKEN) == _asset) return _amount;

        (IPriceProvider provider, ISwapper swapper) = _resolveProviderAndSwapper(_asset);

        bytes memory callData = abi.encodeCall(ISwapper.swapAmountOut, (
            address(QUOTE_TOKEN), _asset, _amount, address(provider), _asset
        ));

        address spender = swapper.spenderToApprove();

        _approve(address(QUOTE_TOKEN), spender, type(uint256).max);

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = address(swapper).delegatecall(callData);
        if (!success) data.revertBytes("SwapAmountOutFailed");

        _approve(address(QUOTE_TOKEN), spender, 0);

        return abi.decode(data, (uint256));
    }

    function _resolveProviderAndSwapper(address _asset) internal view returns (IPriceProvider, ISwapper) {
        IPriceProvider priceProvider = findPriceProvider(_asset);

        ISwapper swapper = _resolveSwapper(priceProvider);

        return (priceProvider, swapper);
    }

    function _resolveSwapper(IPriceProvider priceProvider) internal view returns (ISwapper) {
        ISwapper swapper = swappers[priceProvider];

        if (address(swapper) == address(0)) {
            revert SwapperNotFound();
        }

        return swapper;
    }

    function _approve(address _asset, address _to, uint256 _amount) internal {
        if (!IERC20(_asset).approve(_to, _amount)) {
            revert ApprovalFailed();
        }
    }
}

