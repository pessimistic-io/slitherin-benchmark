pragma solidity ^0.8.0;

import "./BaseCoboSafeModuleAcl.sol";
import "./IAddressAccessControl.sol";

contract OneInchAggregationRouterV5Acl is BaseCoboSafeModuleAcl {
 
    address public tokenWhiteListAcl;
    constructor(address _safeAddress, address _safeModule, address tokenAcl) {
        _setSafeAddressAndSafeModule(_safeAddress, _safeModule);
        tokenWhiteListAcl = tokenAcl;
    }

    function setWhiteListAcl(address acl) external onlyOwner {
        tokenWhiteListAcl = acl;
    }

    function _checkAllAddresses(address[] memory addresses)
        internal
        view
        virtual
    {
        require(IAddressAccessControl(tokenWhiteListAcl).containsAll(addresses), "An unsupported token exists!");
    }

    function _checkAddress(address addr) internal view virtual {
        require(IAddressAccessControl(tokenWhiteListAcl).contains(addr), "An unsupported token exists!");
    }

    function clipperSwapToWithPermit(
        address clipperExchange,
        address payable recipient,
        address srcToken,
        address dstToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 goodUntil,
        bytes32 r,
        bytes32 vs,
        bytes calldata permit
    ) external view onlySelf {
        onlySafeAddress(recipient);
        _checkAddress(srcToken);
        _checkAddress(dstToken);
    }

    function clipperSwap(
        address clipperExchange,
        address srcToken,
        address dstToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 goodUntil,
        bytes32 r,
        bytes32 vs
    ) external view onlySelf {
        _checkAddress(srcToken);
        _checkAddress(dstToken);
    }

    function clipperSwapTo(
        address clipperExchange,
        address payable recipient,
        address srcToken,
        address dstToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 goodUntil,
        bytes32 r,
        bytes32 vs
    ) external view onlySelf {
        onlySafeAddress(recipient);
        _checkAddress(srcToken);
        _checkAddress(dstToken);
    }

    struct SwapDescription {
        address srcToken;
        address dstToken;
        address payable srcReceiver;
        address payable dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
    }

    function swap(
        address executor,
        SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external view onlySelf {
        onlySafeAddress(desc.dstReceiver);
        _checkAddress(desc.srcToken);
        _checkAddress(desc.dstToken);
    }


    function unoswapToWithPermit(
        address payable recipient,
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools,
        bytes calldata permit
    ) external view onlySelf {
        onlySafeAddress(recipient);
        _checkAddress(srcToken);
    }

    function unoswapTo(
        address payable recipient,
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external view onlySelf  {
        onlySafeAddress(recipient);
        _checkAddress(srcToken);
    }


    function unoswap(
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external view onlySelf {
        _checkAddress(srcToken);
    }



    function uniswapV3SwapToWithPermit(
        address payable recipient,
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools,
        bytes calldata permit
    ) external view onlySelf {
        onlySafeAddress(recipient);
        _checkAddress(srcToken);
    }

    function uniswapV3Swap(
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external view onlySelf {
    }

    function uniswapV3SwapTo(
        address payable recipient,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external view onlySelf {
        onlySafeAddress(recipient);
    }
}

