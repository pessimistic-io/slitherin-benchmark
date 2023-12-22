pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";

contract STANDARD is Ownable, ERC721Enumerable{
    string private _uri;
    mapping(address => bool) public minters;
    uint256 public index = 0;
    uint256 public totalNew = 0;
    uint256 public totalEth = 0;
    mapping(uint256 => uint256) public typeMap;

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

    //types 1=ETH, 2=NEW
    function mint(address to, uint256 types) external onlyMinter{
        require((types == 1 || types == 2), 'types value error');
        if(types ==1){
            require((totalEth <= 5000), 'eth max value error');
        }else{
            require((totalNew <= 5000), 'new max value error');
        }
        typeMap[index] == types;
        _mint(to, index);
        index ++;
        if(types ==1){
            totalEth ++;
        }else{
            totalNew ++;
        }
    }

}



