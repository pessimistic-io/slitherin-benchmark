//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ERC20, IERC20 } from "./ERC20.sol";
import { Ownable } from "./Ownable.sol";

contract PepeToken is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 2e25; //20 million with 18 decimals

    error UnderlyingToken();
    error RetrivalFailed();
    error MaxMinted();
    error InsufficientBurnAmount();

    /**
     * treasury:  2,400,000
     * private TGE: 700,000
     * public TGE: 4,000,000
     * liquidity mining: 4,600,000
     * incubator: 1,000,000
     * strategic partnerships: 1,600,000
     * airdrop: 2,100,000
     * team: 3,600,000
     */
    constructor() ERC20("Pepe Governance Token", "PEG") {}

    function mint(address _to, uint256 _amount) external onlyOwner {
        if (_amount + totalSupply() > TOTAL_SUPPLY) revert MaxMinted();
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyOwner {
        if (_amount > balanceOf(_from)) revert InsufficientBurnAmount();
        _burn(_from, _amount);
    }

    /// @dev retrieve stuck tokens
    function retrieve(address _token) external onlyOwner {
        if (_token == address(this)) revert UnderlyingToken();
        IERC20 token = IERC20(_token);
        if (address(this).balance != 0) {
            (bool success, ) = payable(owner()).call{ value: address(this).balance }("");
            if (!success) revert RetrivalFailed();
        }

        token.transfer(owner(), token.balanceOf(address(this)));
    }
}

