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

    struct MintingData {
        uint256 amountIndex;
        uint256 amountWNATIVETotal;
        uint256[] amountWNATIVEs;
        address[] bestRouters;
        uint256[] amountComponents;
    }

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
        if (recipient == address(0)) {
            revert Errors.Index_ZeroAddress();
        }

        address bestRouter;
        MintingData memory mintingData;

        (amountToken, bestRouter, mintingData) = _getMintingDataFromToken(
            token,
            amountTokenMax
        );

        if (amountToken > amountTokenMax) {
            revert Errors.Index_AboveMaxAmount();
        }

        if (mintingData.amountIndex < amountIndexMin) {
            revert Errors.Index_BelowMinAmount();
        }

        amountIndex = mintingData.amountIndex;

        IERC20Upgradeable(token).safeTransferFrom(
            _msgSender(),
            address(this),
            amountToken
        );

        uint256 amountTokenSpent = _swapTokenForExactToken(
            bestRouter,
            mintingData.amountWNATIVETotal,
            amountToken,
            token,
            wNATIVE
        );

        if (amountTokenSpent != amountToken) {
            revert Errors.Index_WrongSwapAmount();
        }

        uint256 amountWNATIVESpent = _mintExactIndexFromWNATIVE(
            mintingData,
            recipient
        );

        if (amountWNATIVESpent != mintingData.amountWNATIVETotal) {
            revert Errors.Index_WrongSwapAmount();
        }

        emit Mint(_msgSender(), recipient, token, amountToken, amountIndex);
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
        if (recipient == address(0)) {
            revert Errors.Index_ZeroAddress();
        }

        uint256 amountWNATIVE = _burnExactIndexForWNATIVE(amountIndex);

        (uint256 amountTokenOut, address bestRouter) = _getAmountOutMax(
            routers[token],
            amountWNATIVE,
            wNATIVE,
            token
        );

        amountToken = _swapExactTokenForToken(
            bestRouter,
            amountWNATIVE,
            amountTokenOut,
            wNATIVE,
            token
        );

        if (amountToken != amountTokenOut) {
            revert Errors.Index_WrongSwapAmount();
        }

        if (amountToken < amountTokenMin) {
            revert Errors.Index_BelowMinAmount();
        }

        IERC20Upgradeable(token).safeTransfer(recipient, amountToken);

        emit Burn(_msgSender(), recipient, token, amountToken, amountIndex);
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

        (amountToken, , mintingData) = _getMintingDataFromToken(
            token,
            amountTokenMax
        );

        amountIndex = mintingData.amountIndex;
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

        (amountToken, ) = _getAmountOutMax(
            routers[token],
            amountWNATIVE,
            wNATIVE,
            token
        );
    }

    /**
     * @dev Rebalances the index strategy by adjusting the weights of the components.
     * @param targetWeights The target weights for each component.
     */
    function rebalance(uint256[] calldata targetWeights) external onlyOwner {
        if (components.length != targetWeights.length) {
            revert Errors.Index_WrongTargetWeightsLength();
        }

        uint256 amountWNATIVETotal;
        uint256[] memory requiredWNATIVEs = new uint256[](components.length);
        uint256 requiredWNATIVETotal;

        uint256 indexTotalSupply = indexToken.totalSupply();

        for (uint256 i = 0; i < components.length; i++) {
            if (weights[components[i]] > targetWeights[i]) {
                // Convert component to wNATIVE.
                uint256 amountComponent;

                if (targetWeights[i] == 0) {
                    // To avoid rounding errors.
                    amountComponent = IERC20Upgradeable(components[i])
                        .balanceOf(address(this));
                } else {
                    amountComponent =
                        ((weights[components[i]] - targetWeights[i]) *
                            indexTotalSupply) /
                        Constants.PRECISION;
                }

                (
                    uint256 amountWNATIVEOut,
                    address bestRouter
                ) = _getAmountOutMax(
                        routers[components[i]],
                        amountComponent,
                        components[i],
                        wNATIVE
                    );

                uint256 balanceComponent = IERC20Upgradeable(components[i])
                    .balanceOf(address(this));

                if (amountComponent > balanceComponent) {
                    amountComponent = balanceComponent;
                }

                uint256 amountWNATIVE = _swapExactTokenForToken(
                    bestRouter,
                    amountComponent,
                    amountWNATIVEOut,
                    components[i],
                    wNATIVE
                );

                if (amountWNATIVE != amountWNATIVEOut) {
                    revert Errors.Index_WrongSwapAmount();
                }

                amountWNATIVETotal += amountWNATIVE;
            } else if (weights[components[i]] < targetWeights[i]) {
                // Calculate how much wNATIVE is required to buy component.
                uint256 amountComponent = ((targetWeights[i] -
                    weights[components[i]]) * indexTotalSupply) /
                    Constants.PRECISION;

                (uint256 amountWNATIVE, ) = _getAmountInMin(
                    routers[components[i]],
                    amountComponent,
                    wNATIVE,
                    components[i]
                );

                requiredWNATIVEs[i] = amountWNATIVE;
                requiredWNATIVETotal += amountWNATIVE;
            }
        }

        if (amountWNATIVETotal == 0) {
            revert Errors.Index_WrongTargetWeights();
        }

        // Convert wNATIVE to component.
        for (uint256 i = 0; i < components.length; i++) {
            if (requiredWNATIVEs[i] == 0) {
                continue;
            }

            uint256 amountWNATIVE = (requiredWNATIVEs[i] * amountWNATIVETotal) /
                requiredWNATIVETotal;

            (uint256 amountComponentOut, address bestRouter) = _getAmountOutMax(
                routers[components[i]],
                amountWNATIVE,
                wNATIVE,
                components[i]
            );

            uint256 amountComponent = _swapExactTokenForToken(
                bestRouter,
                amountWNATIVE,
                amountComponentOut,
                wNATIVE,
                components[i]
            );

            if (amountComponent != amountComponentOut) {
                revert Errors.Index_WrongSwapAmount();
            }
        }

        // Adjust component's weights.
        for (uint256 i = 0; i < components.length; i++) {
            uint256 componentBalance = IERC20Upgradeable(components[i])
                .balanceOf(address(this));

            weights[components[i]] =
                (componentBalance * Constants.PRECISION) /
                indexTotalSupply;
        }
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
     * @dev Mints the exact index amount of the index token by swapping components with wNATIVE.
     * @param mintingData The minting data containing information about the components and routers.
     * @param recipient The address to receive the minted index tokens.
     * @return amountWNATIVESpent The amount of wNATIVE spent during the minting process.
     */
    function _mintExactIndexFromWNATIVE(
        MintingData memory mintingData,
        address recipient
    ) internal returns (uint256 amountWNATIVESpent) {
        for (uint256 i = 0; i < components.length; i++) {
            if (mintingData.amountComponents[i] == 0) {
                continue;
            }

            amountWNATIVESpent += _swapTokenForExactToken(
                mintingData.bestRouters[i],
                mintingData.amountComponents[i],
                mintingData.amountWNATIVEs[i],
                wNATIVE,
                components[i]
            );
        }

        indexToken.mint(recipient, mintingData.amountIndex);
    }

    /**
     * @dev Burns the exact index amount of the index token and swaps components for wNATIVE.
     * @param amountIndex The amount of index tokens to burn.
     * @return amountWNATIVE The amount of wNATIVE received from burning the index tokens.
     */
    function _burnExactIndexForWNATIVE(uint256 amountIndex)
        internal
        returns (uint256 amountWNATIVE)
    {
        for (uint256 i = 0; i < components.length; i++) {
            if (weights[components[i]] == 0) {
                continue;
            }

            uint256 amountComponent = (amountIndex * weights[components[i]]) /
                Constants.PRECISION;

            (uint256 amountWNATIVEOut, address bestRouter) = _getAmountOutMax(
                routers[components[i]],
                amountComponent,
                components[i],
                wNATIVE
            );

            amountWNATIVE += _swapExactTokenForToken(
                bestRouter,
                amountComponent,
                amountWNATIVEOut,
                components[i],
                wNATIVE
            );
        }

        indexToken.burnFrom(_msgSender(), amountIndex);
    }

    /**
     * @dev Calculates the minting data for the exact index amount.
     * @param amountIndex The exact index amount to mint.
     * @return mintingData The minting data containing information about the components, routers, and wNATIVE amounts.
     */
    function _getMintingDataForExactIndex(uint256 amountIndex)
        internal
        view
        returns (MintingData memory mintingData)
    {
        mintingData.amountIndex = amountIndex;
        mintingData.amountWNATIVEs = new uint256[](components.length);
        mintingData.bestRouters = new address[](components.length);
        mintingData.amountComponents = new uint256[](components.length);

        for (uint256 i = 0; i < components.length; i++) {
            if (weights[components[i]] == 0) {
                continue;
            }

            mintingData.amountComponents[i] =
                (amountIndex * weights[components[i]]) /
                Constants.PRECISION;

            (
                mintingData.amountWNATIVEs[i],
                mintingData.bestRouters[i]
            ) = _getAmountInMin(
                routers[components[i]],
                mintingData.amountComponents[i],
                wNATIVE,
                components[i]
            );

            mintingData.amountWNATIVETotal += mintingData.amountWNATIVEs[i];
        }
    }

    /**
     * @dev Calculates the minting data from the given token and maximum token amount.
     * @param token The token to mint from.
     * @param amountTokenMax The maximum token amount to use for minting.
     * @return amountToken The actual token amount used for minting.
     * @return bestRouter The best router to use for minting.
     * @return mintingData The minting data containing information about the components, routers, and wNATIVE amounts.
     */
    function _getMintingDataFromToken(address token, uint256 amountTokenMax)
        internal
        view
        returns (
            uint256 amountToken,
            address bestRouter,
            MintingData memory mintingData
        )
    {
        (uint256 amountWNATIVE, ) = _getAmountOutMax(
            routers[token],
            amountTokenMax,
            token,
            wNATIVE
        );

        mintingData = _getMintingDataFromWNATIVE(amountWNATIVE);

        (amountToken, bestRouter) = _getAmountInMin(
            routers[token],
            mintingData.amountWNATIVETotal,
            token,
            wNATIVE
        );
    }

    /**
     * @dev Calculates the minting data from the given wNATIVE amount.
     * @param amountWNATIVEMax The maximum wNATIVE amount to use for minting.
     * @return mintingData The minting data containing information about the components, routers, and wNATIVE amounts.
     */
    function _getMintingDataFromWNATIVE(uint256 amountWNATIVEMax)
        internal
        view
        returns (MintingData memory mintingData)
    {
        MintingData memory mintingDataUnit = _getMintingDataForExactIndex(
            Constants.PRECISION
        );

        uint256 amountIndex = type(uint256).max;

        for (uint256 i = 0; i < components.length; i++) {
            if (mintingDataUnit.amountWNATIVEs[i] == 0) {
                continue;
            }

            uint256 amountWNATIVE = (amountWNATIVEMax *
                mintingDataUnit.amountWNATIVEs[i]) /
                mintingDataUnit.amountWNATIVETotal;

            (uint256 amountComponent, ) = _getAmountOutMax(
                routers[components[i]],
                amountWNATIVE,
                wNATIVE,
                components[i]
            );

            amountIndex = MathUpgradeable.min(
                amountIndex,
                (amountComponent * Constants.PRECISION) / weights[components[i]]
            );
        }

        mintingData = _getMintingDataForExactIndex(amountIndex);
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

            (uint256 amountWNATIVEOut, ) = _getAmountOutMax(
                routers[components[i]],
                amountComponent,
                components[i],
                wNATIVE
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

    /**
     * @dev Swaps exact token for token using a specific router.
     * @param router The router address to use for swapping.
     * @param amountIn The exact amount of input tokens.
     * @param amountOutMin The minimum amount of output tokens to receive.
     * @param tokenIn The input token address.
     * @param tokenOut The output token address.
     * @return amountOut The amount of output tokens received.
     */
    function _swapExactTokenForToken(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256 amountOut) {
        if (tokenIn == tokenOut) {
            return amountIn;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        amountOut = SwapAdapter
            .Setup(dexs[router], router, pairData[router][tokenIn][tokenOut])
            .swapExactTokensForTokens(amountIn, amountOutMin, path);
    }

    /**
     * @dev Swaps a specific amount of `tokenIn` for an exact amount of `tokenOut` using a specified router.
     * @param router The address of the router contract to use for the swap.
     * @param amountOut The exact amount of `tokenOut` tokens to receive.
     * @param amountInMax The maximum amount of `tokenIn` tokens to be used for the swap.
     * @param tokenIn The address of the token to be swapped.
     * @param tokenOut The address of the token to receive.
     * @return amountIn The actual amount of `tokenIn` tokens used for the swap.
     */
    function _swapTokenForExactToken(
        address router,
        uint256 amountOut,
        uint256 amountInMax,
        address tokenIn,
        address tokenOut
    ) internal returns (uint256 amountIn) {
        if (tokenIn == tokenOut) {
            return amountOut;
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        amountIn = SwapAdapter
            .Setup(dexs[router], router, pairData[router][tokenIn][tokenOut])
            .swapTokensForExactTokens(amountOut, amountInMax, path);
    }

    /**
     * @dev Calculates the maximum amount of `tokenOut` tokens that can be received for a given `amountIn` of `tokenIn` tokens,
     *      and identifies the best router to use for the swap among a list of routers.
     * @param _routers The list of router addresses to consider for the swap.
     * @param amountIn The amount of `tokenIn` tokens.
     * @param tokenIn The address of the token to be swapped.
     * @param tokenOut The address of the token to receive.
     * @return amountOutMax The maximum amount of `tokenOut` tokens that can be received for the given `amountIn`.
     * @return bestRouter The address of the best router to use for the swap.
     */
    function _getAmountOutMax(
        address[] memory _routers,
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 amountOutMax, address bestRouter) {
        if (tokenIn == tokenOut) {
            return (amountIn, address(0));
        }

        if (_routers.length == 0) {
            revert Errors.Index_WrongPair(tokenIn, tokenOut);
        }

        amountOutMax = type(uint256).min;

        for (uint256 i = 0; i < _routers.length; i++) {
            address router = _routers[i];

            uint256 amountOut = SwapAdapter
                .Setup(
                    dexs[router],
                    router,
                    pairData[router][tokenIn][tokenOut]
                )
                .getAmountOut(amountIn, tokenIn, tokenOut);

            if (amountOut > amountOutMax) {
                amountOutMax = amountOut;
                bestRouter = router;
            }
        }
    }

    /**
     * @dev Calculates the minimum amount of `tokenIn` tokens required to receive a given `amountOut` of `tokenOut` tokens,
     *      and identifies the best router to use for the swap among a list of routers.
     * @param _routers The list of router addresses to consider for the swap.
     * @param amountOut The amount of `tokenOut` tokens to receive.
     * @param tokenIn The address of the token to be swapped.
     * @param tokenOut The address of the token to receive.
     * @return amountInMin The minimum amount of `tokenIn` tokens required to receive the given `amountOut`.
     * @return bestRouter The address of the best router to use for the swap.
     */
    function _getAmountInMin(
        address[] memory _routers,
        uint256 amountOut,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 amountInMin, address bestRouter) {
        if (tokenIn == tokenOut) {
            return (amountOut, address(0));
        }

        if (_routers.length == 0) {
            revert Errors.Index_WrongPair(tokenIn, tokenOut);
        }

        amountInMin = type(uint256).max;

        for (uint256 i = 0; i < _routers.length; i++) {
            address router = _routers[i];

            uint256 amountIn = SwapAdapter
                .Setup(
                    dexs[router],
                    router,
                    pairData[router][tokenIn][tokenOut]
                )
                .getAmountIn(amountOut, tokenIn, tokenOut);

            if (amountIn < amountInMin) {
                amountInMin = amountIn;
                bestRouter = router;
            }
        }
    }
}

