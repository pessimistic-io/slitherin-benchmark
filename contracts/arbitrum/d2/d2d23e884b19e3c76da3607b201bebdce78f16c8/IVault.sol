// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

interface IVault {
    function deposit(
        address,
        address,
        uint256
    ) external;

    function withdraw(
        address,
        address,
        uint256
    ) external;

    function deploy(
        string memory name,
        string memory symbol,
        uint256 origin,
        bytes memory origin_hash,
        uint8 origin_decimals
    ) external returns(address);

    function mint(
        address token_address,
        address to,
        uint256 amount
    ) external;

    function burn(
        address,
        address,
        uint256
    ) external;

}
