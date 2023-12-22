// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./DEXBaseACL.sol";

interface IPool {
    function token0() external view returns (address);

    function token1() external view returns (address);
}

contract OneinchV5Authorizer is DEXBaseACL {
    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    bytes32 public constant NAME = "1inchV5Authorizer";
    uint256 public constant VERSION = 1;

    // For 1inch aggreator data.
    uint256 private constant _REVERSE_MASK = 0x8000000000000000000000000000000000000000000000000000000000000000;
    uint256 private constant _ADDRESS_MASK = 0x000000000000000000000000ffffffffffffffffffffffffffffffffffffffff;
    uint256 private constant _ONE_FOR_ZERO_MASK = 1 << 255;

    address public immutable router;
    address public immutable weth;

    /// @dev When deploying on chain the correct `weth` and `router` should be set.
    constructor(address _owner, address _caller, address _weth, address _router) DEXBaseACL(_owner, _caller) {
        weth = _weth;
        router = _router;
    }

    function contracts() public view override returns (address[] memory _contracts) {
        _contracts = new address[](1);
        _contracts[0] = router;
    }

    function _getToken(address _token) internal view returns (address) {
        return (_token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE || _token == address(0)) ? weth : _token;
    }

    // Checking functions.

    function swap(address, SwapDescription calldata _desc, bytes calldata, bytes calldata) external view {
        checkRecipient(_desc.dstReceiver);
        address srcToken = _getToken(_desc.srcToken);
        address dstToken = _getToken(_desc.dstToken);
        swapInOutTokenCheck(srcToken, dstToken);
    }

    //already restrict recipient must be msg.sender in 1inch contract
    function unoswap(address _srcToken, uint256, uint256, uint256[] calldata pools) external view {
        uint256 lastPool = pools[pools.length - 1];
        IPool lastPair = IPool(address(uint160(lastPool & _ADDRESS_MASK)));
        address srcToken = _getToken(_srcToken);
        bool isReversed = lastPool & _REVERSE_MASK == 0;
        address tokenOut = isReversed ? lastPair.token1() : lastPair.token0();
        swapInOutTokenCheck(srcToken, tokenOut);
    }

    function uniswapV3Swap(uint256 amount, uint256 minReturn, uint256[] calldata pools) external view {
        uint256 lastPoolUint = pools[pools.length - 1];
        uint256 firstPoolUint = pools[0];
        IPool firstPool = IPool(address(uint160(firstPoolUint)));
        IPool lastPool = IPool(address(uint160(lastPoolUint)));
        bool zeroForOneFirstPool = firstPoolUint & _ONE_FOR_ZERO_MASK == 0;
        bool zeroForOneLastPool = lastPoolUint & _ONE_FOR_ZERO_MASK == 0;
        address srcToken = zeroForOneFirstPool ? firstPool.token0() : firstPool.token1();
        address dstToken = zeroForOneLastPool ? lastPool.token1() : firstPool.token0();
        swapInOutTokenCheck(srcToken, dstToken);
    }
}

