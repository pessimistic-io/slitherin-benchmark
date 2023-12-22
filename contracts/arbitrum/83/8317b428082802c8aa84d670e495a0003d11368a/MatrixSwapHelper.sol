// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./IUniswapV2Router02.sol";
import "./EnumerableSet.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import "./IUniswapV2Pair.sol";
//import "hardhat/console.sol";
import "./IERC20Metadata.sol";


/// @title Swap Helper to perform swaps and setting routes in matrix strategies
contract MatrixSwapHelper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public unirouter;

    /// @dev Enumerable set of external tokens and routers
    /// strategy can interact with
    EnumerableSet.AddressSet internal whitelistedAddresses;

    struct SwapPath {
        address unirouter;
        address[] path;
    }

    mapping(bytes32 => SwapPath) internal swapPaths;

    constructor(address _uniRouter) {
        unirouter = _uniRouter;
    }

    function getWhitelistedAddresses()
        public
        virtual
        returns (address[] memory)
    {
        return whitelistedAddresses.values();
    }

    function getSwapPath(address _fromToken, address _toToken)
        public
        view
        virtual
        returns (SwapPath memory _swapPath)
    {
        bytes32 _swapKey = keccak256(abi.encodePacked(_fromToken, _toToken));
        require(swapPaths[_swapKey].unirouter != address(0), "path-not-found");
        return swapPaths[_swapKey];
    }

    function _setSwapPath(
        address _fromToken,
        address _toToken,
        address _unirouter,
        address[] memory _path
    ) internal virtual {
        require(_path[0] == _fromToken, "invalid-path");
        require(_path[_path.length - 1] == _toToken, "invalid-path");
        _checkPath(_path);

        bytes32 _swapKey = keccak256(abi.encodePacked(_fromToken, _toToken));
        address _router = _unirouter == address(0) ? unirouter : _unirouter;

        _checkRouter(_router);

        swapPaths[_swapKey] = SwapPath(_router, _path);
    }

    /// @dev Checks that tokens in path are whitelisted
    /// @notice Override this to skip checks
    function _checkPath(address[] memory _path) internal virtual {
        for (uint256 i; i < _path.length; i++)
        {
            //console.log(_path[i]);
            require(
                whitelistedAddresses.contains(_path[i]),
                "token-not-whitelisted"
            );
        }
    }

    /// @dev Checks that router for swap is whitelisted
    /// @notice Override this to skip checks
    function _checkRouter(address _router) internal virtual {
        require(
            whitelistedAddresses.contains(_router),
            "router-not-whitelisted"
        );
    }

    function _swap(
        address _fromToken,
        address _toToken,
        uint256 _amount
    ) internal virtual returns (uint256 _toTokenAmount) {
        if (_fromToken == _toToken) return _amount;
        SwapPath memory _swapPath = getSwapPath(_fromToken, _toToken);

        IERC20(_fromToken).safeApprove(_swapPath.unirouter, 0);
        IERC20(_fromToken).safeApprove(_swapPath.unirouter, type(uint256).max);
        
        // debugging: uncomment this block
        
        // console.log("_fromToken:", IERC20Metadata(_fromToken).symbol());
        // console.log("_toToken", IERC20Metadata(_toToken).symbol());
        // console.log("_path:");
        // for (uint i; i < _swapPath.path.length; i++) {
        //     console.log(_swapPath.path[i]);
        //     console.log(IERC20Metadata(_swapPath.path[i]).symbol());
        // }

        uint256 _toTokenBefore = IERC20(_toToken).balanceOf(address(this));
        IUniswapV2Router02(_swapPath.unirouter).swapExactTokensForTokens(
            _amount,
            0,
            _swapPath.path,
            address(this),
            block.timestamp
        );

        _toTokenAmount =
            IERC20(_toToken).balanceOf(address(this)) -
            _toTokenBefore;
    }
}

