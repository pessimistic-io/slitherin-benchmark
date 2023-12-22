pragma solidity >0.8.0;

import "./ERC721.sol";
//import "hardhat/console.sol";

/*
                           _                                                  _   
   ___    _ __     ___    | |__    ___      o O O __ __ __  ___     ___    __| |  
  (_-<   | '  \   / _ \   | / /   / -_)    o      \ V  V / / -_)   / -_)  / _` |  
  /__/_  |_|_|_|  \___/   |_\_\   \___|   TS__[O]  \_/\_/  \___|   \___|  \__,_|  
_|"""""|_|"""""|_|"""""|_|"""""|_|"""""| {======|_|"""""|_|"""""|_|"""""|_|"""""| 
"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-'./o--000'"`-0-0-'"`-0-0-'"`-0-0-'"`-0-0-' 
*/

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
}

interface IMETADATA {
    function tokenuri(uint id) external view returns(string memory);
    function getRaw(uint _id) external view returns (string memory);
}

contract MRPP is ERC721 {

    uint public MAX_SUPPLY;
    uint public TOTAL_SUPPLY;
    uint public MINTPRICE;
    uint public godnumber;
    uint public onceanhour;
    uint public priceofhonor;
    uint public onehour;
    IUniswapV2Pair public rnglp;

    struct Info {
        address owner;
        IMETADATA metadata;
    }
    Info private info;

    struct PPMAN {
        uint id;
        uint wins;                          // battle wins
        uint losses;                        // battle losses
        uint honor;                         // changed the rng god number $$$  changegodnumber()     diff dickhead based on id % 10
        uint donations;                     // amount person has donated  $$$  helpthenurses()       gets crown or balls or boobs
        uint girth;                         // times user called swordfight                          thickens dick
        uint nepotism;                      // patriarchy 
    }
    mapping(uint => PPMAN) public PPMEN;

    constructor(
        IMETADATA _metadata
    ) payable ERC721("MRPP", "MRPP") {
        info.owner = msg.sender;
        MAX_SUPPLY = 1000;
        info.metadata = _metadata;
        onceanhour = block.timestamp;
        priceofhonor = 0;
        onehour = 30;
        MINTPRICE = 0;
        TOTAL_SUPPLY = 0;
        godnumber = 80081355;
        rnglp = IUniswapV2Pair(0x905dfCD5649217c42684f23958568e533C711Aa3);
        for (uint i = 0; i < 50; i++) {     // mint 50 for me to give to my friends who like me for ME they are MY friends for reals 
            _mint(msg.sender, i);
            PPMEN[i] = PPMAN(i, 0, 0, 0, 0, 0, 0);
            TOTAL_SUPPLY++;
        }
    }

	modifier _onlyOwner() {
		require(msg.sender == owner(), "not my daddy");
		_;
	}

    function mint(uint _amount) public payable {
        require(msg.value >= MINTPRICE * _amount, "kek");
        require(TOTAL_SUPPLY + _amount < MAX_SUPPLY, "maxed out");
        if (MINTPRICE == 0) {
            require(_amount <= 5, "greedy fuck");
        }
        for (uint i = 0; i < _amount; i++) {
            PPMEN[TOTAL_SUPPLY] = PPMAN(TOTAL_SUPPLY, 0, 0, 0, 0, 0, 0);
            _safeMint(msg.sender, TOTAL_SUPPLY);
            TOTAL_SUPPLY++;
        }
    }

    function swordfight(uint _whoiam) public {
        require(block.timestamp > onceanhour, "rest your peen");
        require(ownerOf[_whoiam] == msg.sender, "not mr pp");
        onceanhour = block.timestamp + onehour;
        uint lol = rnglp.price0CumulativeLast();
        for (uint i = 0; i < TOTAL_SUPPLY; i++) {
            uint rng = uint(keccak256(abi.encodePacked(block.number, blockhash(block.number - 69), ownerOf[i], msg.sender, lol, i, godnumber))); // fuck gas kid nut tf up
            if (rng % 2 == 1) {
                PPMEN[i].wins = PPMEN[i].wins + 1;
            } else {
                PPMEN[i].losses = PPMEN[i].losses + 1;
            }
            //bytes memory s = bytes(_uint2str(rng));
            //console.logBytes1(s[0]);
        }   
        PPMEN[_whoiam].girth = PPMEN[_whoiam].girth + 1;
    }

    function changegodnumber(uint _whywouldyoudothis, uint _id) public payable {
        require(msg.value >= priceofhonor, "needs more honor");
        require(ownerOf[_id] != address(0), "badbadbadbadbad");
        PPMEN[_id].honor = PPMEN[_id].honor + 1;
        godnumber = _whywouldyoudothis;
    }

    function helpthenurses(uint _id) public payable {
        require(msg.value > 0);
        PPMEN[_id].donations = PPMEN[_id].donations + msg.value;
    }

    //  view funcs  //

    function doesthisguyownone(address _hotguy) public view returns (bool, uint[] memory) {
        uint count = 0;
        for (uint i = 0; i < TOTAL_SUPPLY; i++) {
            if (ownerOf[i] == _hotguy) {
                count++;
            }
        }
        if (count == 0) return (false, new uint[](0));
        uint[] memory ids = new uint[](count);
        uint index = 0;
        for (uint i = 0; i < TOTAL_SUPPLY; i++) {
            if (ownerOf[i] == _hotguy) {
                ids[index] = i;
                index++;
            }
        }
        return (true, ids);
    }

    function owner() public view returns (address) {
		return info.owner;
	}

    function getrawsvg(uint _id) public view returns (string memory) {
        return info.metadata.getRaw(_id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        require(ownerOf[id] != address(0), "0x0 bad");
        string memory s = info.metadata.tokenuri(id); 
        return s;
    }

    function getPPInfo(uint _tokenid) external view returns(PPMAN memory) {
        PPMAN memory p = PPMEN[_tokenid];
        return p;
    }

    //  admin funcs //

    function nepotism(uint _id, uint _points) public _onlyOwner {
        PPMEN[_id].nepotism = _points;
    }

    function milady() public _onlyOwner {
        uint bal = address(this).balance;
        address payable bigdick = payable(info.owner);
        (bool ok,) = bigdick.call{value: bal}("");
        require(ok, "this is bad");
    }

    function honorcostslikewhat(uint _cost) public _onlyOwner {
        priceofhonor = _cost;
    }

    function timeisanillusion(uint _onehour) public _onlyOwner {
        onehour = _onehour;
    }

    function setMetaData(IMETADATA _metadata) public _onlyOwner {
        info.metadata = _metadata;
    }

    function changernglp(IUniswapV2Pair _somecoollp) public _onlyOwner {
        rnglp = _somecoollp;
    }

    function setOwner(address _owner) external _onlyOwner {
		info.owner = _owner;
	}

    function changeMintPrice(uint _amount) external _onlyOwner {
        MINTPRICE = _amount;
    }


    //  contract fillers  //

    function toBytes(uint256 x) internal pure returns (bytes memory b) {
        b = new bytes(32);
        assembly { mstore(add(b, 32), x) }
    }

    function _uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

}


