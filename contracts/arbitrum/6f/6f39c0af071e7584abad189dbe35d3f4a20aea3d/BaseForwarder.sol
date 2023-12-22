//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.7;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./ICurve.sol";

abstract contract BaseForwarder is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    struct CurvePoolInfo {
        address router;
        address pool;
        address jToken;
        int128 i;
        int128 j;
    }

    /// @dev Basis points or bps, set to 10 000 (equal to 1/10000). Used to express relative values (fees)
    uint256 public constant BPS_DENOMINATOR = 10000;

    mapping(address => CurvePoolInfo) pools;

    /* ========== ERRORS ========== */

    error AdminBadRole();

    /* ========== MODIFIERS ========== */

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert AdminBadRole();
        _;
    }

    /* ========== INITIALIZERS ========== */

    function __BaseForwarder_init() internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __BaseForwarder_init_unchained();
    }

    function __BaseForwarder_init_unchained() internal initializer {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /* ========== METHODS ========== */

    function addUnwrapPool(
        address _pool,
        int128 _i,
        address _iToken,
        int128 _j,
        address _jToken
    ) external onlyAdmin {
        CurvePoolInfo storage target = pools[_iToken];
        target.pool = _pool;
        target.jToken = _jToken;
        target.i = _i;
        target.j = _j;
    }

    function addUnwrapRouter(
        address _router,
        address _pool,
        int128 _i,
        address _iToken,
        int128 _j,
        address _jToken
    ) external onlyAdmin {
        CurvePoolInfo storage target = pools[_iToken];
        target.router = _router;
        target.pool = _pool;
        target.jToken = _jToken;
        target.i = _i;
        target.j = _j;
    }

    function getUnwrapToken(address _wrappedToken) public view returns (address) {
        return pools[_wrappedToken].jToken;
    }

    // swaps _tokenIn to some target token defined by pools[]
    function _swapFrom(
        IERC20 _tokenIn,
        uint256 _amountIn,
        uint256 _minAmountOut
    )
        internal
        virtual
        returns (
            address tokenOut,
            uint256 amountOut,
            bool success
        )
    {
        CurvePoolInfo memory target = pools[address(_tokenIn)];

        if (target.pool == address(0)) {
            return (address(0), 0, false);
        }


        if (target.router == address(0)) {
            _tokenIn.approve(target.pool, _amountIn);

            ICurve(target.pool).exchange_underlying(
                target.i,
                target.j,
                _amountIn,
                _minAmountOut
            );
        } else {
            _tokenIn.approve(target.router, _amountIn);

            ICurve(target.router).exchange_underlying(
                target.pool,
                target.i,
                target.j,
                _amountIn,
                _minAmountOut,
                address(this)
            );
        }

        _tokenIn.approve(target.pool, 0);

        tokenOut = target.jToken;
        amountOut = IERC20(target.jToken).balanceOf(address(this));
        success = amountOut > 0;
    }

    function externalCall(address destination, bytes memory data)
        internal
        returns (bool result)
    {
        uint256 dataLength = data.length;
        assembly {
            let x := mload(0x40) // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                gas(), // pass all gas to external call
                destination,
                0, //value,
                d,
                dataLength, // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0 // Output is ignored, therefore the output size is zero
            )
        }
    }
}

