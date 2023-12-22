// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./ERC20_IERC20Upgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ContextUpgradeable } from "./ContextUpgradeable.sol";
import { ERC165Upgradeable } from "./ERC165Upgradeable.sol";
import { MathUpgradeable } from "./MathUpgradeable.sol";

import { IIndexInit } from "./IIndexInit.sol";
import { IIndexLimits } from "./IIndexLimits.sol";
import { IIndexOracle } from "./IIndexOracle.sol";
import { IIndexStrategy } from "./IIndexStrategy.sol";
import { IIndexToken } from "./IIndexToken.sol";
import { Constants } from "./Constants.sol";
import { Errors } from "./Errors.sol";
import { SwapAdapter } from "./SwapAdapter.sol";
import { MintingData, MintParams, BurnParams, ManagementParams } from "./Common.sol";
import { IndexStrategyMint } from "./IndexStrategyMint.sol";
import { IndexStrategyBurn } from "./IndexStrategyBurn.sol";
import { IndexStrategyManagement } from "./IndexStrategyManagement.sol";
import { IndexStrategyUtils } from "./IndexStrategyUtils.sol";

/**
 * @title IndexStrategyUpgradeable
 * @dev An abstract contract that implements various interfaces and extends other contracts, providing functionality for managing index strategies.
 */
abstract contract IndexStrategyUpgradeable is
    ERC165Upgradeable,
    ReentrancyGuardUpgradeable,
    ContextUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    IIndexInit,
    IIndexLimits,
    IIndexStrategy
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SwapAdapter for SwapAdapter.Setup;

    address public wNATIVE;

    address[] public whitelistedTokens;
    IIndexToken public indexToken;

    address[] public components;
    mapping(address => uint256) public weights; // A mapping from `component` to its `weight`.
    mapping(address => address[]) public routers; // A mapping from `token` to its list of `routers`.
    mapping(address => SwapAdapter.DEX) public dexs; // A mapping from `router` to its type of `DEX`.
    mapping(address => mapping(address => mapping(address => SwapAdapter.PairData))) // A mapping from `router`, `tokenIn` and `tokenOut` to `PairData`.
        public pairData;

    IIndexOracle public oracle;
    uint256 public equityValuationLimit;

    address public constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256[8] private __gap;

    /**
     * @dev Modifier to allow only whitelisted tokens to access a function.
     * @param token The address of the token to check.
     */
    modifier onlyWhitelistedToken(address token) {
        if (!isTokenWhitelisted(token)) {
            revert Errors.Index_NotWhitelistedToken(token);
        }

        _;
    }

    /**
     * @dev Modifier to check if the equity valuation limit has not been reached.
     */
    modifier whenNotReachedEquityValuationLimit() {
        _;

        if (equityValuation(true, true) > equityValuationLimit) {
            revert Errors.Index_ExceedEquityValuationLimit();
        }
    }

    /**
     * @dev Initializes the IndexStrategyUpgradeable contract.
     * @param initParams The parameters needed for initialization.
     */
    // solhint-disable-next-line
    function __IndexStrategyUpgradeable_init(
        IndexStrategyInitParams calldata initParams
    ) internal onlyInitializing {
        __ERC165_init();
        __ReentrancyGuard_init();
        __Context_init();
        __Ownable_init();
        __Pausable_init();

        wNATIVE = initParams.wNATIVE;

        indexToken = IIndexToken(initParams.indexToken);

        for (uint256 i = 0; i < initParams.components.length; i++) {
            components.push(initParams.components[i].token);

            _setWeight(
                initParams.components[i].token,
                initParams.components[i].weight
            );
        }

        for (uint256 i = 0; i < initParams.swapRoutes.length; i++) {
            addSwapRoute(
                initParams.swapRoutes[i].token,
                initParams.swapRoutes[i].router,
                initParams.swapRoutes[i].dex,
                initParams.swapRoutes[i].pairData
            );
        }

        addWhitelistedTokens(initParams.whitelistedTokens);

        setOracle(initParams.oracle);

        setEquityValuationLimit(initParams.equityValuationLimit);
    }

    /**
     * @dev Pauses the contract, preventing certain functions from being called.
     */
    function pause() external onlyOwner {
        super._pause();
    }

    /**
     * @dev Unpauses the contract, allowing the paused functions to be called.
     */
    function unpause() external onlyOwner {
        super._unpause();
    }

    /**
     * @dev Checks if a particular interface is supported by the contract.
     * @param interfaceId The interface identifier.
     * @return A boolean value indicating whether the interface is supported.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            interfaceId == type(IIndexStrategy).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev It ensures that Ether is only received from wNATIVE and not from any other addresses.
     */
    receive() external payable {
        if (msg.sender != wNATIVE) {
            revert Errors.Index_ReceivedNativeTokenDirectly();
        }
    }

    /**
     * @dev Mints index tokens in exchange for a specified token.
     * @param token The address of the token to be swapped.
     * @param amountTokenMax The maximum amount of the token to be swapped.
     * @param amountIndexMin The minimum amount of index tokens to be minted.
     * @param recipient The address that will receive the minted index tokens.
     * @return amountIndex The amount of index tokens minted.
     * @return amountToken The amount of tokens swapped.
     */
    function mintIndexFromToken(
        address token,
        uint256 amountTokenMax,
        uint256 amountIndexMin,
        address recipient
    )
        external
        nonReentrant
        whenNotPaused
        onlyWhitelistedToken(token)
        whenNotReachedEquityValuationLimit
        returns (uint256 amountIndex, uint256 amountToken)
    {
        (amountIndex, amountToken) = IndexStrategyMint.mintIndexFromToken(
            MintParams(
                token,
                amountTokenMax,
                amountIndexMin,
                recipient,
                _msgSender(),
                wNATIVE,
                components,
                indexToken
            ),
            pairData,
            dexs,
            weights,
            routers
        );

        emit Mint(_msgSender(), recipient, token, amountToken, amountIndex);
    }

    /**
     * @dev Mints index tokens by swapping the native asset (such as Ether).
     * @param amountIndexMin The minimum amount of index tokens expected to be minted.
     * @param recipient The address that will receive the minted index tokens.
     * @return amountIndex The actual amount of index tokens minted.
     * @return amountNATIVE The actual amount of the native asset swapped.
     */
    function mintIndexFromNATIVE(uint256 amountIndexMin, address recipient)
        external
        payable
        nonReentrant
        whenNotPaused
        whenNotReachedEquityValuationLimit
        returns (uint256 amountIndex, uint256 amountNATIVE)
    {
        (amountIndex, amountNATIVE) = IndexStrategyMint.mintIndexFromNATIVE(
            MintParams(
                NATIVE,
                msg.value,
                amountIndexMin,
                recipient,
                _msgSender(),
                wNATIVE,
                components,
                indexToken
            ),
            pairData,
            dexs,
            weights,
            routers
        );

        emit Mint(_msgSender(), recipient, NATIVE, amountNATIVE, amountIndex);
    }

    /**
     * @dev Burns index tokens in exchange for a specified token.
     * @param token The address of the token to be received.
     * @param amountTokenMin The minimum amount of tokens to be received.
     * @param amountIndex The amount of index tokens to be burned.
     * @param recipient The address that will receive the tokens.
     * @return amountToken The amount of tokens received.
     */
    function burnExactIndexForToken(
        address token,
        uint256 amountTokenMin,
        uint256 amountIndex,
        address recipient
    )
        external
        nonReentrant
        whenNotPaused
        onlyWhitelistedToken(token)
        returns (uint256 amountToken)
    {
        amountToken = IndexStrategyBurn.burnExactIndexForToken(
            BurnParams(
                token,
                amountTokenMin,
                amountIndex,
                recipient,
                _msgSender(),
                wNATIVE,
                components,
                indexToken
            ),
            pairData,
            dexs,
            weights,
            routers
        );
        emit Burn(_msgSender(), recipient, token, amountToken, amountIndex);
    }

    /**
     * @dev Burns index tokens in exchange for the native asset (such as Ether).
     * @param amountNATIVEMin The minimum amount of the native asset expected to be received.
     * @param amountIndex The amount of index tokens to be burned.
     * @param recipient The address that will receive the native asset.
     * @return amountNATIVE The actual amount of the native asset received.
     */
    function burnExactIndexForNATIVE(
        uint256 amountNATIVEMin,
        uint256 amountIndex,
        address recipient
    ) external nonReentrant whenNotPaused returns (uint256 amountNATIVE) {
        amountNATIVE = IndexStrategyBurn.burnExactIndexForNATIVE(
            BurnParams(
                NATIVE,
                amountNATIVEMin,
                amountIndex,
                recipient,
                _msgSender(),
                wNATIVE,
                components,
                indexToken
            ),
            pairData,
            dexs,
            weights,
            routers
        );

        emit Burn(_msgSender(), recipient, NATIVE, amountNATIVE, amountIndex);
    }

    /**
     * @dev Retrieves the amount of index tokens that will be minted for a specified token.
     * @param token The address of the token to be swapped.
     * @param amountTokenMax The maximum amount of the token to be swapped.
     * @return amountIndex The amount of index tokens that will be minted.
     * @return amountToken The amount of tokens to be swapped.
     */
    function getAmountIndexFromToken(address token, uint256 amountTokenMax)
        external
        view
        onlyWhitelistedToken(token)
        returns (uint256 amountIndex, uint256 amountToken)
    {
        MintingData memory mintingData;

        (amountToken, , mintingData) = IndexStrategyMint
            .getMintingDataFromToken(
                MintParams(
                    token,
                    amountTokenMax,
                    0,
                    address(0),
                    _msgSender(),
                    wNATIVE,
                    components,
                    indexToken
                ),
                pairData,
                dexs,
                weights,
                routers
            );

        amountIndex = mintingData.amountIndex;
    }

    /**
     * @dev Retrieves the amount of index tokens that will be minted in exchange for the native asset (such as Ether).
     * @param amountNATIVEMax The maximum amount of the native asset that can be swapped.
     * @return amountIndex The estimated amount of index tokens that will be minted.
     * @return amountNATIVE The actual amount of the native asset that will be swapped.
     */
    function getAmountIndexFromNATIVE(uint256 amountNATIVEMax)
        external
        view
        returns (uint256 amountIndex, uint256 amountNATIVE)
    {
        MintingData memory mintingData = IndexStrategyMint
            .getMintingDataFromWNATIVE(
                amountNATIVEMax,
                MintParams(
                    wNATIVE,
                    amountNATIVEMax,
                    0,
                    address(0),
                    _msgSender(),
                    wNATIVE,
                    components,
                    indexToken
                ),
                routers,
                pairData,
                dexs,
                weights
            );

        amountIndex = mintingData.amountIndex;
        amountNATIVE = mintingData.amountWNATIVETotal;
    }

    /**
     * @dev Retrieves the amount of tokens that will be received for a specified amount of index tokens.
     * @param token The address of the token to be received.
     * @param amountIndex The amount of index tokens to be burned.
     * @return amountToken The amount of tokens that will be received.
     */
    function getAmountTokenFromExactIndex(address token, uint256 amountIndex)
        external
        view
        onlyWhitelistedToken(token)
        returns (uint256 amountToken)
    {
        uint256 amountWNATIVE = _getAmountWNATIVEFromExactIndex(amountIndex);

        (amountToken, ) = IndexStrategyUtils.getAmountOutMax(
            routers[token],
            amountWNATIVE,
            wNATIVE,
            token,
            dexs,
            pairData
        );
    }

    /**
     * @dev Retrieves the estimated amount of the native asset (such as Ether) that can be received by burning a specified amount of index tokens.
     * @param amountIndex The amount of index tokens to be burned.
     * @return amountNATIVE The estimated amount of the native asset that will be received.
     */
    function getAmountNATIVEFromExactIndex(uint256 amountIndex)
        external
        view
        returns (uint256 amountNATIVE)
    {
        amountNATIVE = _getAmountWNATIVEFromExactIndex(amountIndex);
    }

    /**
     * @dev Rebalances the index strategy by adjusting the weights of the components.
     * @param targetWeights The target weights for each component.
     */
    function rebalance(uint256[] calldata targetWeights) external onlyOwner {
        IndexStrategyManagement.rebalance(
            ManagementParams(wNATIVE, components, indexToken, targetWeights),
            pairData,
            dexs,
            weights,
            routers
        );
    }

    /**
     * @dev Adds a component to the index strategy.
     * @param component The address of the component token.
     */
    function addComponent(address component) external onlyOwner {
        for (uint256 i = 0; i < components.length; i++) {
            if (components[i] == component) {
                revert Errors.Index_ComponentAlreadyExists(component);
            }
        }

        components.push(component);
    }

    /**
     * @dev Adds a swap route for swapping tokens.
     * @param token The address of the token to be swapped.
     * @param router The address of the router contract.
     * @param dex The type of decentralized exchange (DEX) used by the router.
     * @param _pairData The pair data for the router and tokens.
     */
    function addSwapRoute(
        address token,
        address router,
        SwapAdapter.DEX dex,
        SwapAdapter.PairData memory _pairData
    ) public onlyOwner {
        _addRouter(token, router);

        _setDEX(router, dex);

        _setPairData(router, token, wNATIVE, _pairData);
    }

    /**
     * @dev Adds multiple tokens to the whitelist.
     * @param tokens The addresses of the tokens to be added.
     */
    function addWhitelistedTokens(address[] memory tokens) public onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isTokenWhitelisted(tokens[i])) {
                whitelistedTokens.push(tokens[i]);
            }
        }
    }

    /**
     * @dev Removes a component from the index strategy.
     * @param component The address of the component token to be removed.
     */
    function removeComponent(address component) external onlyOwner {
        for (uint256 i = 0; i < components.length; i++) {
            if (components[i] == component) {
                if (weights[component] != 0) {
                    revert Errors.Index_ComponentHasNonZeroWeight(component);
                }

                components[i] = components[components.length - 1];
                components.pop();
                break;
            }
        }
    }

    /**
     * @dev Removes a swap route for swapping tokens.
     * @param token The address of the token to be swapped.
     * @param router The address of the router contract to be removed.
     */
    function removeSwapRoute(address token, address router) external onlyOwner {
        _removeRouter(token, router);

        _setPairData(
            router,
            token,
            wNATIVE,
            SwapAdapter.PairData(address(0), abi.encode(0))
        );
    }

    /**
     * @dev Removes multiple tokens from the whitelist.
     * @param tokens The addresses of the tokens to be removed.
     */
    function removeWhitelistedTokens(address[] memory tokens) public onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            for (uint256 j = 0; j < whitelistedTokens.length; j++) {
                if (whitelistedTokens[j] == tokens[i]) {
                    whitelistedTokens[j] = whitelistedTokens[
                        whitelistedTokens.length - 1
                    ];
                    whitelistedTokens.pop();
                    break;
                }
            }
        }
    }

    /**
     * @dev Sets the equity valuation limit for the index strategy.
     * @param _equityValuationLimit The new equity valuation limit.
     */
    function setEquityValuationLimit(uint256 _equityValuationLimit)
        public
        onlyOwner
    {
        equityValuationLimit = _equityValuationLimit;
    }

    /**
     * @dev Sets the oracle contract for the index strategy.
     * @param _oracle The address of the oracle contract.
     */
    function setOracle(address _oracle) public onlyOwner {
        oracle = IIndexOracle(_oracle);
    }

    /**
     * @dev Retrieves the addresses of all components in the index strategy.
     * @return An array of component addresses.
     */
    function allComponents() external view override returns (address[] memory) {
        return components;
    }

    /**
     * @dev Retrieves the addresses of all whitelisted tokens.
     * @return An array of whitelisted token addresses.
     */
    function allWhitelistedTokens() external view returns (address[] memory) {
        return whitelistedTokens;
    }

    /**
     * @dev Calculates the equity valuation of the index strategy.
     * @param maximize A boolean indicating whether to maximize the valuation.
     * @param includeAmmPrice A boolean indicating whether to include the AMM price in the valuation.
     * @return The equity valuation of the index strategy.
     */
    function equityValuation(bool maximize, bool includeAmmPrice)
        public
        view
        virtual
        returns (uint256);

    /**
     * @dev Checks if a token is whitelisted.
     * @param token The address of the token to check.
     * @return bool Returns true if the token is whitelisted, false otherwise.
     */
    function isTokenWhitelisted(address token) public view returns (bool) {
        for (uint256 i = 0; i < whitelistedTokens.length; i++) {
            if (whitelistedTokens[i] == token) {
                return true;
            }
        }

        return false;
    }

    /**
     * @dev Calculates the amount of wNATIVE received from the exact index amount.
     * @param amountIndex The exact index amount.
     * @return amountWNATIVE The amount of wNATIVE received.
     */
    function _getAmountWNATIVEFromExactIndex(uint256 amountIndex)
        internal
        view
        returns (uint256 amountWNATIVE)
    {
        for (uint256 i = 0; i < components.length; i++) {
            if (weights[components[i]] == 0) {
                continue;
            }

            uint256 amountComponent = (amountIndex * weights[components[i]]) /
                Constants.PRECISION;

            (uint256 amountWNATIVEOut, ) = IndexStrategyUtils.getAmountOutMax(
                routers[components[i]],
                amountComponent,
                components[i],
                wNATIVE,
                dexs,
                pairData
            );

            amountWNATIVE += amountWNATIVEOut;
        }
    }

    /**
     * @dev Sets the weight of a token.
     * @param token The token address.
     * @param weight The weight of the token.
     */
    function _setWeight(address token, uint256 weight) internal {
        weights[token] = weight;
    }

    /**
     * @dev Adds a router for a token.
     * @param token The token address.
     * @param router The router address.
     */
    function _addRouter(address token, address router) internal {
        if (token == address(0)) {
            revert Errors.Index_ZeroAddress();
        }

        for (uint256 i = 0; i < routers[token].length; i++) {
            if (routers[token][i] == router) {
                return;
            }
        }

        routers[token].push(router);
    }

    /**
     * @dev Sets the DEX (Decentralized Exchange) for a router.
     * @param router The router address.
     * @param dex The DEX to set.
     */
    function _setDEX(address router, SwapAdapter.DEX dex) internal {
        if (router == address(0)) {
            revert Errors.Index_ZeroAddress();
        }

        if (dexs[router] != SwapAdapter.DEX.None) {
            return;
        }

        dexs[router] = dex;
    }

    /**
     * @dev Sets the pair data for a router, token0, and token1.
     * @param router The router address.
     * @param token0 The first token address.
     * @param token1 The second token address.
     * @param _pairData The pair data to set.
     */
    function _setPairData(
        address router,
        address token0,
        address token1,
        SwapAdapter.PairData memory _pairData
    ) internal {
        if (token0 == address(0) || token1 == address(0)) {
            revert Errors.Index_ZeroAddress();
        }

        if (pairData[router][token0][token1].pair != address(0)) {
            return;
        }

        pairData[router][token0][token1] = _pairData;
        pairData[router][token1][token0] = _pairData;
    }

    /**
     * @dev Removes a router for a token.
     * @param token The token address.
     * @param router The router address to remove.
     */
    function _removeRouter(address token, address router) internal {
        for (uint256 i = 0; i < routers[token].length; i++) {
            if (routers[token][i] == router) {
                routers[token][i] = routers[token][routers[token].length - 1];
                routers[token].pop();
                break;
            }
        }
    }
}

