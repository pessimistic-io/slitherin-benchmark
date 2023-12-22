pragma solidity 0.8.17;

import {Auth, GlobalACL} from "./Auth.sol";
import {Multicall} from "./Multicall.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {IHandlerContract} from "./IHandlerContract.sol";
import {ISwapManager} from "./ISwapManager.sol";

contract WhitelistedTokenRegistry is GlobalACL {
    event UpdatedWhitelistedToken(address indexed _token, bool _isWhitelisted);
    event UpdatedIsWhitelistingEnabled(bool _isEnabled);

    /// @notice whitelisted tokens to/from which swaps allowed
    mapping(address => bool) public whitelistedTokens;
    /// @notice whitelisting in effect
    bool public isWhitelistingEnabled = true;

    constructor(Auth _auth) GlobalACL(_auth) {}

    function updateWhitelistedToken(
        address _token,
        bool _isWhitelisted
    ) external onlyConfigurator {
        whitelistedTokens[_token] = _isWhitelisted;
        emit UpdatedWhitelistedToken(_token, _isWhitelisted);
    }

    function updateIsWhitelistingEnabled(
        bool _isWhitelistingEnabled
    ) external onlyConfigurator {
        isWhitelistingEnabled = _isWhitelistingEnabled;
        emit UpdatedIsWhitelistingEnabled(_isWhitelistingEnabled);
    }

    function isWhitelistedToken(address _token) external view returns (bool) {
        if (isWhitelistingEnabled) {
            return whitelistedTokens[_token];
        }
        return true;
    }
}

library PositionManagerRouterLib {
    error NotWhitelistedToken();
    error UnknownHandlerContract();

    function executeSwap(
        ISwapManager _swapManager,
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        uint _minOut,
        bytes calldata _data,
        WhitelistedTokenRegistry whitelistedTokenRegistry,
        mapping(ISwapManager => bool) storage swapHandlers,
        mapping(IHandlerContract => bool) storage handlerContracts
    ) external returns (uint _amountOut) {
        if (
            !whitelistedTokenRegistry.isWhitelistedToken(_tokenIn) ||
            !whitelistedTokenRegistry.isWhitelistedToken(_tokenOut)
        ) revert NotWhitelistedToken();

        bool isSwapHandler = swapHandlers[_swapManager];
        bool isHandler = handlerContracts[_swapManager];
        if (!isSwapHandler || !isHandler) {
            revert UnknownHandlerContract();
        }

        bytes memory ret = _delegatecall(
            address(_swapManager),
            abi.encodeCall(
                ISwapManager.swap,
                (_tokenIn, _tokenOut, _amountIn, _minOut, _data)
            )
        );
        (_amountOut) = abi.decode(ret, (uint));
    }

    function _delegatecall(
        address _target,
        bytes memory _data
    ) internal returns (bytes memory ret) {
        bool success;
        (success, ret) = _target.delegatecall(_data);
        if (!success) {
            /// @solidity memory-safe-assembly
            assembly {
                let length := mload(ret)
                let start := add(ret, 0x20)
                revert(start, length)
            }
        }
        return ret;
    }
}

/**
 * @title PositionManagerRouter
 * @author Umami DAO
 * @dev This abstract contract is a base implementation for a position manager router.
 *      It handles execution, callbacks, and swap operations on handler contracts.
 */
abstract contract PositionManagerRouter {

    error UnknownCallback();
    error CallbackHandlerNotSet();
    error UnknownHandlerContract();
    error OnlySelf();
    error NotWhitelistedToken();

    /// @dev Emitted when a callback handler is updated.
    event CallbackHandlerUpdated(
        bytes4 indexed _sig,
        address indexed _handler,
        bool _enabled
    );

    /// @dev Emitted when a handler contract is updated.
    event HandlerContractUpdated(address indexed _contract, bool _enabled);

    /// @dev Emitted when a default handler contract is updated.
    event DefaultHandlerContractUpdated(
        bytes4 indexed _sig,
        address indexed _handler
    );

    /// @dev Emitted when a swap handler is updated.
    event SwapHandlerUpdated(address indexed _handled, bool _enabled);
    event WhitelistedTokenUpdated(address indexed _token, bool _isWhitelisted);

    /// @notice mapping of handler contracts and callbacks they can handle
    mapping(IHandlerContract => mapping(bytes4 => bool)) public handlerContractCallbacks;

    /// @notice mapping of allowed handler contracts
    mapping(IHandlerContract => bool) public handlerContracts;

    /// @notice current handler contract, set when `executeWithCallbackHandler` called.
    ///         Useful when multiple handlers can handle same callback. So you specify
    ///         which handler to call.
    address public currentCallbackHandler;

    /// @notice mapping of default handlers for a given method. This is used if currentCallbackHandler
    ///         is not set.
    mapping(bytes4 => IHandlerContract) public defaultHandlers;

    /// @notice whitelisted swap handlers
    mapping(ISwapManager => bool) public swapHandlers;
    /// @notice Whitelisted token registry
    WhitelistedTokenRegistry immutable whitelistedTokenRegistry;

    constructor(WhitelistedTokenRegistry _registry) {
        whitelistedTokenRegistry = _registry;
    }

    /**
     * @notice Updates the handler contract and its associated callbacks.
     * @param _handler The handler contract to be updated.
     * @param _enabled Whether the handler should be enabled or disabled.
     */
    function updateHandlerContract(
        IHandlerContract _handler,
        bool _enabled
    ) public {
        _onlyConfigurator();
        handlerContracts[_handler] = _enabled;
        emit HandlerContractUpdated(address(_handler), _enabled);
        _updateHandlerContractCallbacks(_handler, _enabled);
    }

    /**
     * @notice Updates the default handler contract for a given method signature.
     * @param _sig The method signature of the default handler.
     * @param _handler The handler contract to be set as the default for the given method.
     */
    function updateDefaultHandlerContract(
        bytes4 _sig,
        IHandlerContract _handler
    ) external {
        _onlyConfigurator();
        defaultHandlers[_sig] = _handler;
        emit DefaultHandlerContractUpdated(_sig, address(_handler));
    }

    /**
     * @notice Updates a swap handler and its associated handler contract.
     * @param _manager The swap manager to be updated.
     * @param _enabled Whether the swap handler should be enabled or disabled.
     */
    function updateSwapHandler(ISwapManager _manager, bool _enabled) external {
        _onlyConfigurator();
        updateHandlerContract(_manager, _enabled);
        swapHandlers[_manager] = _enabled;
        emit SwapHandlerUpdated(address(_manager), _enabled);
    }

    /**
     * @notice Executes a call to a handler contract.
     * @param _handler The handler contract to be called.
     * @param data The data to be sent to the handler contract.
     * @return ret The returned data from the handler contract.
     */
    function execute(
        address _handler,
        bytes calldata data
    ) public payable returns (bytes memory ret) {
        _validateExecuteCallAuth();
        bool isSwapHandler = swapHandlers[ISwapManager(_handler)];
        if (isSwapHandler && msg.sender != address(this))
            _onlySwapIssuer();
        bool isHandler = handlerContracts[IHandlerContract(_handler)];
        if (!isHandler) revert UnknownHandlerContract();
        ret = _delegatecall(_handler, data);
    }

    /**
     * @notice Executes a call to a handler contract with the specified `currentCallbackHandler`.
     * @dev `execute` with `currentCallbackHandler` set. Useful when multiple handlers can handle a callback.abi
     *       E.g.: Flash loan callbacks, swap callbacks, etc.
     * @param _handler The handler contract to be called.
     * @param data The data to be sent to the handler contract.
     * @param _callbackHandler The callback handler to be used for this execution.
     * @return ret The returned data from the handler contract.
     */
    function executeWithCallbackHandler(
        address _handler,
        bytes calldata data,
        address _callbackHandler
    )
        external
        payable
        withHandler(_callbackHandler)
        returns (bytes memory ret)
    {
        ret = execute(_handler, data);
    }

    /**
     * @notice Executes a swap against a swap manager.
     * @dev execute swap against a swap manager
     * @param _swapManager The swap manager to execute the swap against.
     * @param _tokenIn The token being provided for the swap.
     * @param _tokenOut The token being requested from the swap.
     * @param _amountIn The amount of `_tokenIn` being provided for the swap.
     * @param _minOut The minimum amount of `_tokenOut` to be received from the swap.
     * @param _data Additional data to be passed to the swap manager.
     * @return _amountOut The amount of `_tokenOut` received from the swap.
     */
    function executeSwap(
        ISwapManager _swapManager,
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        uint _minOut,
        bytes calldata _data
    ) external returns (uint _amountOut) {
        if (msg.sender != address(this)) {
            _onlySwapIssuer();
        }
        _amountOut = PositionManagerRouterLib.executeSwap(
            _swapManager,
            _tokenIn,
            _tokenOut,
            _amountIn,
            _minOut,
            _data,
            whitelistedTokenRegistry,
            swapHandlers,
            handlerContracts
        );
    }

    /**
    * @dev Fallback function which handles callbacks from external contracts.
    *      It forwards the call to the appropriate handler, either the
    *      `currentCallbackHandler` or the default handler for the method signature.
    *      This is necessary to have callback handlers defined in position managers and swap handlers.
    */
    fallback() external payable {
        bytes memory _ret = _handleCallback();

        // bubble up the returned data from the handler
        /// @solidity memory-safe-assembly
        assembly {
            let length := mload(_ret)
            return(add(_ret, 0x20), length)
        }
    }

    /// @dev To be implemented by inheriting contracts to restrict certain functions to a configurator role.
    function _onlyConfigurator() internal virtual;

    /// @dev To be implemented by inheriting contracts to restrict certain functions to a swap issuer role.
    function _onlySwapIssuer() internal virtual;

    /// @dev To be implemented by inheriting contracts to validate the caller's authorization for execute calls.
    function _validateExecuteCallAuth() internal virtual;

    /**
    * @dev Updates the handler contract callbacks based on the provided `_handler` and `_enabled` status.
    * @param _handler The handler contract to update the callbacks for.
    * @param _enabled Whether the handler contract's callbacks should be enabled or disabled.
    */
    function _updateHandlerContractCallbacks(
        IHandlerContract _handler,
        bool _enabled
    ) internal {
        bytes4[] memory handlerSigs = _handler.callbackSigs();
        unchecked {
            for (uint256 i = 0; i < handlerSigs.length; ++i) {
                bytes4 sig = handlerSigs[i];
                handlerContractCallbacks[_handler][sig] = _enabled;
                emit CallbackHandlerUpdated(sig, address(_handler), _enabled);
            }
        }
    }

    /**
    * @dev Handles a callback, i.e. an unknown method that this contract is
    *      not capable of handling.
    *      First tries to check and call `currentCallbackHandler` if it is
    *      set. If it is not set, check and call `defaultHandlers[msg.sig]`.
    *      Also validates that the handler contract is capable of handling
    *      this specific callback.
    * @return ret The returned data from the handler.
    */
    function _handleCallback() internal returns (bytes memory ret) {
        IHandlerContract handler = IHandlerContract(currentCallbackHandler);

        // no transient callback handler set
        if (address(handler) == address(0)) {
            // check if default handler exist for given sig
            handler = defaultHandlers[msg.sig];
            if (handler == IHandlerContract(address(0))) {
                revert CallbackHandlerNotSet();
            }
        }

        if (!handlerContracts[handler]) revert UnknownHandlerContract();

        if (!handlerContractCallbacks[handler][msg.sig]) {
            revert UnknownCallback();
        }

        ret = _delegatecall(address(handler), msg.data);
    }

    /**
    * @dev Performs a delegate call to the specified `_target` with the provided `_data`.
    * @param _target The address to delegate the call to.
    * @param _data The data to send with the delegate call.
    * @return ret The returned data from the delegate call.
    */
    function _delegatecall(
        address _target,
        bytes memory _data
    ) internal returns (bytes memory ret) {
        bool success;
        (success, ret) = _target.delegatecall(_data);
        if (!success) {
            /// @solidity memory-safe-assembly
            assembly {
                let length := mload(ret)
                let start := add(ret, 0x20)
                revert(start, length)
            }
        }
        return ret;
    }

    /**
    * @dev Modifier to ensure the specified `_handler` is a valid handler contract.
    * @param _handler The address of the handler contract to validate.
    */
    modifier withHandler(address _handler) {
        if (!handlerContracts[IHandlerContract(_handler)])
            revert UnknownHandlerContract();

        currentCallbackHandler = _handler;
        _;
        currentCallbackHandler = address(0);
    }

    /// @dev Modifier to ensure the caller of the function is the contract itself.
    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    /// @dev External payable function to receive funds.
    receive() external payable {}
}

