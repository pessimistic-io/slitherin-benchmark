pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./ERC1155Holder.sol";


/*

try not to forget to put a fat smol here ok

*/


contract EpisodeOne is Ownable, ERC1155Holder {

    IERC721 public wSMOL;
    IERC1155 public smolTreasures;      // 0xc5295C6a183F29b7c962dF076819D44E0076860E
    string public baseURI;
    uint public timeToEat; // = 1 days;

    uint public MAX_CHONK_SIZE;
    mapping(uint => uint) public episodeStat;
    mapping(uint => uint) public lastChonk;

    constructor(IERC721 _wsmol, IERC1155 _smolTreasures) {
        wSMOL = _wsmol;
        smolTreasures = _smolTreasures;
        MAX_CHONK_SIZE = 6;
        baseURI = "https://smolart.mypinata.cloud/ipfs/QmTvTJvA6qsDL75M5X8iAmZfMdWdtLNmZsRcmZXaBQAkeC/";
        timeToEat = 1 days;
    }

    function setBaseURI(string memory _baseuri) external onlyOwner {
        baseURI = _baseuri;
    }

    function setMaxChonkSize(uint _size) external onlyOwner {
        MAX_CHONK_SIZE = _size;
    }

    function setTimeToEat(uint _time) external onlyOwner {
        timeToEat = _time;
    }

    function tokenURI(uint _id) public view returns (string memory) {
        return string(abi.encodePacked(baseURI, _uint2str(_id), "/", _uint2str(episodeStat[_id]), ".json"));
    }

    function getEpisodeStat(uint _tokenid) external view returns (uint) {
        return episodeStat[_tokenid];
    }

    function chonkify(uint _id) external {
        require(msg.sender == wSMOL.ownerOf(_id), "not owner");
        require(episodeStat[_id] < MAX_CHONK_SIZE, "try dieting");
        require(lastChonk[_id] + timeToEat < block.timestamp, "not time to eat yet");
        if (episodeStat[_id] == MAX_CHONK_SIZE - 1) {
            require(smolTreasures.balanceOf(msg.sender, 1) >= 50, "need 50 moonrox");
            smolTreasures.safeTransferFrom(msg.sender, address(this), 1, 50, "");  
        }
        episodeStat[_id]++;
        lastChonk[_id] = block.timestamp;
    }

    function _uint2str(uint256 _value) internal pure returns (string memory) {
		uint256 _digits = 1;
		uint256 _n = _value;
		while (_n > 9) {
			_n /= 10;
			_digits++;
		}
		bytes memory _out = new bytes(_digits);
		for (uint256 i = 0; i < _out.length; i++) {
			uint256 _dec = (_value / (10**(_out.length - i - 1))) % 10;
			_out[i] = bytes1(uint8(_dec) + 48);
		}
		return string(_out);
	}
}
