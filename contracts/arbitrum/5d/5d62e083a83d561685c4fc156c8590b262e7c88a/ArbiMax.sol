// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "./ERC20.sol";
import "./Ownable.sol";

contract ArbiMax is ERC20, Ownable {
  ERC20 public usdc;
  uint public ABSOLUT_MAX_SUPPLY = 1000000 * decimalsMultiplier(); // 1 million AMX
  uint public MAX_SUPPLY = ABSOLUT_MAX_SUPPLY;
  uint public pricePerToken = 150000; // 0.15 USDC per AMX
  bool public mintOpen;

  constructor(address _usdc) ERC20("ArbiMax", "AMX") {
    usdc = ERC20(_usdc);
    // 200k -- presale
    // 133,333 -- LP
    // 100k -- team + initial community
    _mint(msg.sender, 433_333 * decimalsMultiplier());
  }

  // _amount in USDC
  function mint(uint _amount) public {
    require(mintOpen, "Minting is currently closed");
    require(_amount >= 1 * usdcDecimalsMultiplier(), "Amount must be greater than 1 USDC");
    require(totalSupply() + _amount < MAX_SUPPLY, "Max supply reached");

    usdc.transferFrom(msg.sender, address(this), _amount);
    // X AMX = _amount (USDC * 10 ** 6) * 1**18  / pricePerToken
    uint numberOfTokens = (_amount * decimalsMultiplier()) / pricePerToken;
    _mint(msg.sender, numberOfTokens);
  }

  function burn(uint _amount) public {
    require(balanceOf(msg.sender) >= _amount, "Not enough AMX");
    _burn(msg.sender, _amount);
  }

  // allows for lowering the max supply under 1M AMX for controlled mints
  function setMaxSupply(uint _maxSupply) public onlyOwner {
    require(_maxSupply <= ABSOLUT_MAX_SUPPLY, "Max supply too high");
    MAX_SUPPLY = _maxSupply;
  }

  function setMintOpen(bool _mintOpen) public onlyOwner {
    mintOpen = _mintOpen;
  }

  function setPricePerToken(uint _pricePerToken) public onlyOwner {
    pricePerToken = _pricePerToken;
  }

  function decimalsMultiplier() private view returns (uint256) {
    return 10 ** decimals();
  }

  function usdcDecimalsMultiplier() private pure returns (uint256) {
    return 10 ** 6;
  }

  // allow withdrawing airdropped tokens
  function withdrawAny(address _token) public onlyOwner {
    ERC20 token = ERC20(_token);
    token.transfer(msg.sender, token.balanceOf(address(this)));
  }
}

