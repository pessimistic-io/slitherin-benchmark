// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {ERC721} from "./ERC721.sol";
import {Counters} from "./Counters.sol";
import {Ownable} from "./Ownable.sol";

import {Strings} from "./Strings.sol";
import {Base64} from "./Base64.sol";

contract ReAnimaPassV2 is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    string constant cName = "Re:Anima Priority Pass";
    string constant cSymbol = "RA PASS";

    uint256 constant SUPPLY_CAP = 2222;
    uint256 constant TEAM_CAP = 222;

    uint256 constant WHITELIST_CAP = SUPPLY_CAP - TEAM_CAP;

    string private passImageURI;

    uint256 public whiteListStartTime;
    uint256 public whiteListEndTime;

    mapping(address => bool) public teamList;
    uint256 public teamCount;
    uint256 public teamMinted;

    // 0, null; 1, white list number; 2, alreay minted
    mapping(address => uint256) public whiteList;
    uint256 public whiteListCount;
    uint256 public whiteListMinted;

    constructor(string memory _passImageURI) ERC721(cName, cSymbol){
        passImageURI = _passImageURI;
    }

    function tokenURI(uint256 id) public view override returns (string memory output) {
        output = string(abi.encodePacked('{'));
        output = string(abi.encodePacked(output, '"name": "', cName, ' #', Strings.toString(id), '",'));
        output = string(abi.encodePacked(output, '"description": "Introducing the exclusive Membership Pass for Re:Anima, the free-to-play web3 RPG. With this limited edition pass card, you will get a head start on this fantastic journey and unlock future perks and utilities within the Re:Anima ecosystem.",'));
        output = string(abi.encodePacked(output, '"image": "', passImageURI, '"}'));

        string memory json = Base64.encode(bytes(output));
        output = string(abi.encodePacked('data:application/json;base64,', json));
    }

    function setPassImageURI(string memory _passImageURI) external onlyOwner {
       passImageURI = _passImageURI;
       emit BatchMetadataUpdate(1, SUPPLY_CAP);
    }
    
    function setPhase(uint256 startTime, uint256 endTime) external onlyOwner {
        require(endTime > startTime && startTime > block.timestamp, "Pass: invalid parameters");
        whiteListStartTime = startTime;
        whiteListEndTime = endTime;
    }

    function mint() external {
        uint256 curTime = block.timestamp;
        if(curTime < whiteListStartTime) {
            require(teamList[msg.sender], "Pass: not a team list member");
            teamList[msg.sender] = false;
            
            teamMinted++;
            require(teamMinted <= TEAM_CAP, "Pass: out of team's supply");

            innerMint();
        } else if(curTime > whiteListStartTime && curTime < whiteListEndTime) {
            require(whiteList[msg.sender] == 1, "Pass: not a white list member");
            whiteList[msg.sender] = 2;
           
            whiteListMinted++;
            require(whiteListMinted <= WHITELIST_CAP, "Pass: out of white list's supply");

            innerMint();
        } else if(curTime > whiteListEndTime) {
            innerMint();
        }
    }

    function innerMint() private {
        _tokenIds.increment();
        uint256 id = _tokenIds.current();
        require(id <= SUPPLY_CAP, "Pass: out of supply");
        
        _safeMint(msg.sender, id);
    }

    function addTeamList(address[] memory list) external onlyOwner {
        require(list.length + teamCount <= TEAM_CAP, "Pass: too many team list");

        for (uint256 i = 0; i < list.length; i++) {
           require(!teamList[list[i]], "Pass: duplicated team mumber");
           teamList[list[i]] = true;
           teamCount++;
        }
    }

    function addwhiteList(address[] memory list) external onlyOwner {
        for (uint256 i = 0; i < list.length; i++) {
            if(whiteList[list[i]] == 0) {
                whiteList[list[i]] = 1;
                whiteListCount++;
            }
        }
    }

    function teamMint(address to, uint256 amount) external onlyOwner {
        for (uint256 i = 0; i < amount; i++) {
            _tokenIds.increment();
            uint256 id = _tokenIds.current();
            require(id <= SUPPLY_CAP, "Pass: out of supply");
            teamMinted++;
            require(teamMinted <= TEAM_CAP, "Pass: out of team cap");
            _safeMint(to, id);
        }
    }

    function totalSupply() public view returns (uint256) {
        return _tokenIds.current();
    }
}
