// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import "./Ownable.sol";

interface IERC20 {
    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract AiPig_Airdrop is Ownable {

    address public AiPig = 0xf629A6a6f052426972187437B8748173C3D91770;

    uint256 public SingleNftDropAmount = 9_310_000_000 * 1_000_000_000_000_000_000;

    constructor() {}

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "Must from real wallet address");
        _;
    }

    function AiPigAirDropByBot(address[] calldata recipients, uint256[] calldata nftAmounts) external onlyOwner {
        for (uint256 i = 0; i < recipients.length; i++)
            require(IERC20(AiPig).transferFrom(msg.sender, recipients[i], nftAmounts[i] * SingleNftDropAmount));
    }

    function setAiPig(address _aipig) external onlyOwner {
        AiPig = _aipig;
    }

    function setSingleNftDropAmount(uint256 _SingleNftDropAmount) external onlyOwner {
        SingleNftDropAmount = _SingleNftDropAmount * 1_000_000_000_000_000_000;
    }

    function withdrawETH(address toUser) external onlyOwner {
        (bool success,) = payable(toUser).call{value : address(this).balance}("");
        require(success, "Transfer failed.");
    }

    receive() external payable {}
}

