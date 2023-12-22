pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./ERC721Holder.sol";
import "./Ownable.sol";
import "./ERC721Enumerable.sol";

interface IEpisodes {
    function tokenURI(uint _id) external view returns (string memory);
    function getEpisodeStat(uint _tokenid) external view returns (uint);
}

contract wSMOL is ERC721Enumerable, ERC721Holder, Ownable {


    uint public currentEpisode;
    mapping(uint => IEpisodes) public episodes;

    IERC721 public SMOLBRAINS;  //0x6325439389E0797Ab35752B4F43a14C004f22A9c

    mapping(uint => uint) public defaultEpisode; // token id => episode id

    constructor(IERC721 _smolbrains) ERC721("Wrapped SMOL", "wSMOL") {
        SMOLBRAINS = _smolbrains; 
        currentEpisode = 0;
    }

    function wrap(uint _tokenid) external {
        SMOLBRAINS.safeTransferFrom(msg.sender, address(this), _tokenid);  
        _safeMint(msg.sender, _tokenid);
    }

    function unwrap(uint _tokenid) external {
        defaultEpisode[_tokenid] = 0;
        safeTransferFrom(msg.sender, address(this), _tokenid);       
        _burn(_tokenid);
        SMOLBRAINS.safeTransferFrom(address(this), msg.sender, _tokenid);
    }

    function tokenURI(uint _id) public view override returns (string memory) {
        if (defaultEpisode[_id] == 0) {
            return episodes[currentEpisode].tokenURI(_id);
        } else {
            uint myEpisode = defaultEpisode[_id];
            return episodes[myEpisode].tokenURI(_id);
        }   
    }

    function getEpisodeStats(uint _tokenid) public view returns (uint[] memory) {
        uint[] memory episodeStats = new uint[](currentEpisode);
        for (uint i = 1; i <= currentEpisode; i++) {
            episodeStats[i-1] = episodes[i].getEpisodeStat(_tokenid);
        }
        return episodeStats;
    }
    

    function setMyFavoriteEpisode(uint _id, uint _episodeId) external {
        require(ownerOf(_id) == msg.sender, "not owner");
        defaultEpisode[_id] = _episodeId;
    }

    // ** //
    function addEpisode(uint _episodeNumber, IEpisodes _episodeAddress) external onlyOwner {
        episodes[_episodeNumber] = _episodeAddress;
    }
    function setCurrentEpisode(uint _episodeNumber) external onlyOwner {
        currentEpisode = _episodeNumber;
    }

}

