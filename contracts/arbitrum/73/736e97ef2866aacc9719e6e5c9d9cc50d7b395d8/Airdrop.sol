// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./ERC20.sol";

contract Airdrop is Ownable {
    mapping(address => uint256) public airdropAmount;
    ERC20 public bobToken;
    bool public canClaim = false;
    uint256 public maxAirdropAmount = 0;
    uint256 public currentAirdropAmount = 0;
    uint256 public feeClaim = 270121330000000; // 0.00027 ETH
    address public receiver;
    bool private locked;

    constructor(address token, uint256 _maxAirdropAmount) {
        bobToken = ERC20(token);
        maxAirdropAmount = _maxAirdropAmount;
        receiver = _msgSender();
    }

    function setClaimable(bool _canClaim) external onlyOwner {
        canClaim = _canClaim;
    }

    function setAirdropAmount(
        address[] memory _addresses,
        uint256[] memory _amount
    ) external onlyOwner {
        require(
            _addresses.length == _amount.length,
            "Airdrop: addresses and amounts length mismatch"
        );
        for (uint256 i = 0; i < _addresses.length; i++) {
            airdropAmount[_addresses[i]] = _amount[i];
        }
    }

    function setMaxAirdropAmount(uint256 _maxAirdropAmount) external onlyOwner {
        maxAirdropAmount = _maxAirdropAmount;
    }

    modifier nonReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    function claim() public nonReentrant {
        require(canClaim, "Airdrop: claiming is not allowed");
        require(
            airdropAmount[_msgSender()] > 0,
            "Airdrop: you are not eligible for airdrop"
        );
        require(
            bobToken.balanceOf(address(this)) >= airdropAmount[_msgSender()],
            "Airdrop: contract does not have enough balance"
        );
        require(
            currentAirdropAmount + airdropAmount[_msgSender()] <=
                maxAirdropAmount,
            "Airdrop: airdrop limit reached"
        );
        if (feeClaim > 0) {
            (bool success, ) = receiver.call{value: feeClaim}("");
            require(success, "Airdrop: fee transfer failed");
        }
        uint256 amount = airdropAmount[_msgSender()];
        airdropAmount[_msgSender()] = 0;
        bobToken.transfer(_msgSender(), amount);
    }

    function setFeeClaim(uint256 _feeClaim) public onlyOwner {
        feeClaim = _feeClaim;
    }

    function setReceiver(address _receiver) public onlyOwner {
        receiver = _receiver;
    }

    function withdrawToken() external onlyOwner {
        bobToken.transfer(_msgSender(), bobToken.balanceOf(address(this)));
    }
}

