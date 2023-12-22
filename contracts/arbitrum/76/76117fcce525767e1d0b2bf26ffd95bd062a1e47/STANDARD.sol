pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC721Enumerable.sol";
import "./Counters.sol";
import "./SafeMath.sol";

contract STANDARD is Ownable, ERC721Enumerable{
    string private _uri;
    mapping(address => bool) public minters;
    uint256 public index = 0;

    modifier onlyMinter(){
        require(minters[msg.sender], "onlyMinter");
        _;
    }

    constructor(string memory name, string memory symbol, string memory uri) ERC721(name, symbol){
        _uri = uri;
        minters[msg.sender] = true;
    }

    function _baseURI() internal view override returns (string memory) {
        return _uri;
    }

    function setBaseUri(string calldata uri) external onlyOwner{
        _uri = uri;
    }

    function setMinter(address account, bool enable) external onlyOwner{
        minters[account] = enable;
    }

    function mint(address to) external onlyMinter{
        _mint(to, index);
        index ++;
    }

}



