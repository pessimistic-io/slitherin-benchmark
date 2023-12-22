// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;
// import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "./ERC20.sol";
import "./Ownable.sol";


contract XVIP is ERC20,Ownable{

    uint256 constant MAX_SUPPLY = 1e9 * 1e18; // cap
    address public minter ;
    event MinterChange(address minter);

    modifier onlyMinter() {
        require(minter == msg.sender, 'onlyMinter');
        _;
    }
 
    constructor()ERC20("XFANS.VIP","XVIP"){
    }

    function cap() public pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function setMinter(address minter_)external onlyOwner{
        minter = minter_;
    }

    //0x40c10f19
    function mint(address _to, uint256 _amount) public onlyMinter {
        _mint(_to, _amount);
        require(totalSupply()<MAX_SUPPLY,"cap exceeded");
        // return true;
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

}
