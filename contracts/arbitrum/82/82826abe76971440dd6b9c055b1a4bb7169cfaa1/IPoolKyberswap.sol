//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

interface IPoolKyberswap {
    //https://polygonscan.com/address/0x546C79662E028B661dFB4767664d0273184E4dD1#code
    // function MINIMUM_LIQUIDITY() external view returns (uint256);

    // function PERMIT_TYPEHASH() external view returns (bytes32);

    // function allowance(
    //     address owner,
    //     address spender
    // ) external view returns (uint256);

    // function ampBps() external view returns (uint32);

    // function approve(address spender, uint256 amount) external returns (bool);

    // function balanceOf(address account) external view returns (uint256);

    // function burn(
    //     address to
    // ) external returns (uint256 amount0, uint256 amount1);

    // function decimals() external view returns (uint8);

    // function decreaseAllowance(
    //     address spender,
    //     uint256 subtractedValue
    // ) external returns (bool);

    // function domainSeparator() external view returns (bytes32);

    // function factory() external view returns (address);

    // function getReserves()
    //     external
    //     view
    //     returns (uint112 _reserve0, uint112 _reserve1);

    function getTradeInfo()
        external
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint112 _vReserve0,
            uint112 _vReserve1,
            uint256 _feeInPrecision
        );

    // function increaseAllowance(
    //     address spender,
    //     uint256 addedValue
    // ) external returns (bool);

    // function initialize(
    //     address _token0,
    //     address _token1,
    //     uint32 _ampBps,
    //     uint24 _feeUnits
    // ) external;

    // function kLast() external view returns (uint256);

    // function mint(address to) external returns (uint256 liquidity);

    // function name() external view returns (string memory);

    // function nonces(address) external view returns (uint256);

    // function permit(
    //     address owner,
    //     address spender,
    //     uint256 value,
    //     uint256 deadline,
    //     uint8 v,
    //     bytes32 r,
    //     bytes32 s
    // ) external;

    // function skim(address to) external;

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes memory callbackData
    ) external;

    // function symbol() external view returns (string memory);

    // function sync() external;

    function token0() external view returns (address);

    function token1() external view returns (address);

    // function totalSupply() external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    // function transferFrom(
    //     address sender,
    //     address recipient,
    //     uint256 amount
    // ) external returns (bool);
}

