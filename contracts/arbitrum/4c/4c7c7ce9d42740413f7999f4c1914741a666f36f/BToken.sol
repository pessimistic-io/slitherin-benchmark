// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";
import "./IbToken.sol";

contract BToken is ERC20, Ownable, IbToken {
    
    uint MAX_SUPPLY = 500_000 * 10 ** 18;

    address tokenAddress;

    modifier onlyTokenTest() {
        require(
            tokenAddress == _msgSender(),
            "Caller is not the token contrat"
        );
        _;
    }

    constructor() ERC20("BToken", "BToken") {}

    function setTokenAddress(address addr) external onlyOwner {
        tokenAddress = addr;
    }

    function mint(address account, uint amount) external onlyTokenTest override  {
        require(totalSupply() <= MAX_SUPPLY, 'Max supply reached');
        _mint(account, amount);
    }

    receive() external payable {}
}
