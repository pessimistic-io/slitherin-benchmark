// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20Capped.sol";
import "./Ownable.sol";
import "./ISociogramManager.sol";

/**
 * @title SociogramMemberToken
 * @dev ERC20-compatible token contract of a Sociogram member's issued tokens.
 */
contract SociogramMemberToken is ERC20, ERC20Burnable, ERC20Capped, Ownable {
    ISociogramManager public immutable MANAGER;
    IERC20 public immutable BASE_TOKEN;
    address public immutable ISSUER;

    /**
     * @dev Constructor of the SociogramMemberToken contract. Owned by SociogramManager
     * @param _issuer The address of the issuer of the token.
     * @param _tokenName The name of the token.
     * @param _tokenSymbol The symbol of the token.
     */
    constructor(
        address _issuer,
        string memory _tokenName, 
        string memory _tokenSymbol
    ) ERC20(_tokenName, _tokenSymbol) ERC20Capped(10000000 ether){
        MANAGER = ISociogramManager(owner());
        BASE_TOKEN = MANAGER.BASE_TOKEN();
        ISSUER = _issuer;
    }

    function _mint(address _to, uint256 _amount) internal override(ERC20, ERC20Capped){
        super._mint(_to, _amount);
    }

    /**
     * @dev Mints tokens to the specified address. Used during token purchase from SociogramManager
     * @param _to The address to which tokens will be minted.
     * @param _amount The amount of tokens to mint.
     */
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /**
     * @dev Allows the issuer to claim the accumulated fee in BASE_TOKEN.
     */
    function claimFee() public {
        require(msg.sender == ISSUER, "SociogramMemberToken: FORBIDDEN");
        BASE_TOKEN.transfer(ISSUER, BASE_TOKEN.balanceOf(address(this)));
    }

    /**
     * @dev Gets the accumulated fee in BASE_TOKEN.
     * @return The amount of earned fee.
     */
    function getEarnedFee() public view returns(uint256){
        return(BASE_TOKEN.balanceOf(address(this)));
    }
}
