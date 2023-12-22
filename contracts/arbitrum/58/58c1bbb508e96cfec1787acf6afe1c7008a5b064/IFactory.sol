pragma solidity ^0.8.0;

enum GatewayType {
    ERC20MintBurn,
    ERC20MintBurnFrom,
    ERC20Pool,
    ERC721MintBurn,
    ERC721Pool,
    ERC1155MintBurn,
    ERC1155Pool,
    ERC677MintBurn,
    ERC677MintBurnFrom,
    ERC677Pool
}

interface IFactory {
    function create(
        address anyCall,
        address token,
        address owner,
        uint256 feeType,
        GatewayType gatewayType
    ) external payable returns (address);
}

