pragma solidity ^0.8.9;

import "./IERC20.sol";

interface MER20 {
    // 铸造方法
    function mint(address _recipient) external payable;
}

// 铸造合约
contract MERMint {
    // 构造函数(nft合约地址, 归集地址)
    constructor(address ERC20, address owner) payable {
        // 铸造(0.05购买总价)(5购买数量)
        MER20(ERC20).mint{value: 0.0005 ether}(address(this));
        // 归集
        IERC20(ERC20).transferFrom(
            address(this),
            owner,
            IERC20(ERC20).balanceOf(address(this))
        );
        // 自毁(收款地址,归集地址)
        selfdestruct(payable(owner));
    }
}

// 工厂合约
contract MintFactory {
    function deploy(address merAddress, uint count) public payable {
        address owner = msg.sender;
        // 用抢购数量进行循环
        for (uint i; i < count; i++) {
            // 部署合约(抢购总价)(NFT合约地址,所有者地址)
            new MERMint{value: 0.0005 ether}(merAddress, owner);
        }
    }
}
