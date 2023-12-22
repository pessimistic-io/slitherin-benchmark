// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
import "./ERC1155.sol";
import "./ERC2345.sol";


contract Registry is ERC2345{

    event Created_Unique_Digital(address receiver, uint256 version, string unique_digital_id, string owner_id, string payload, uint256 time);
    event Uniqueness_of_Unique_Digital(uint256 version, string unique_digital_id, string owner_id, string fingerprint_method, string fingerprint, string payload, uint256 time);
    event Presentation_of_Unique_Digital(uint256 version, string unique_digital_id, string owner_id, string token_method, string token, string payload, uint256 time);
    event Transfer_of_Ownership(address from, address to, uint256 version, string unique_digital_id, string old_owner_id, string new_owner_id, string payload, uint256 time, uint256 units);
    event Delete_Unique_Digital(uint256 version, string unique_digital_id, string owner_id, uint256 amount, uint256 time, string payload);

    uint256 public counter = 0;
    mapping(string=>uint256) public match_nfts;
    mapping(string=>bool) public exists_nfts;
    struct Metadata{
        string fingerprint;
        string name;
        string description;
        string location;
        string payload;
    }
    mapping(string=>Metadata) public metainfo;
    uint256 private max = 100000000;

    constructor() ERC2345("https://registry.activeimage.io/images/{id}") {
    }

    function createUniqueDigital(address _receiver, uint256 _version, string memory _unique_digital_id, string memory _owner_id, string memory _name, string memory _description, string memory _location, string memory _payload, uint256 _time) public {
        require(exists_nfts[_unique_digital_id] == false, "NFT already present!");
        match_nfts[_unique_digital_id] = counter;
        counter ++;
        _mint(_receiver, match_nfts[_unique_digital_id], 1, max, "");
        metainfo[_unique_digital_id].fingerprint = _unique_digital_id;
        metainfo[_unique_digital_id].name = _name;
        metainfo[_unique_digital_id].description = _description;
        metainfo[_unique_digital_id].location = _location;
        metainfo[_unique_digital_id].payload = _payload;
        exists_nfts[_unique_digital_id] = true;
        emit Created_Unique_Digital(_receiver, _version, _unique_digital_id, _owner_id, _payload, _time);
    }

    function balanceofNFT(address _account, string memory _unique_digital_id) public view returns (uint256){
        require(exists_nfts[_unique_digital_id] == true, "NFT does not exist!");
        uint256 balance;
        balance = balanceOf(_account, match_nfts[_unique_digital_id]);
        return balance;
    }

    function balanceofUnits(address _account, string memory _unique_digital_id) public view returns (uint256){
        require(exists_nfts[_unique_digital_id] == true, "NFT does not exist!");
        uint256 balance;
        balance = balanceOfUnits(_account, match_nfts[_unique_digital_id]);
        return balance;
    }

    function getID(string memory _unique_digital_id) public view returns (uint256){
        require(exists_nfts[_unique_digital_id] == true, "NFT does not exist!");
        uint256 id;
        id = match_nfts[_unique_digital_id];
        return id;
    }

    function getMetadata(string memory _unique_digital_id) public view returns (string memory, string memory , string memory, string memory, string memory){
        return (metainfo[_unique_digital_id].fingerprint, metainfo[_unique_digital_id].name, metainfo[_unique_digital_id].description, metainfo[_unique_digital_id].location, metainfo[_unique_digital_id].payload);
    }

    function transferToken(address _from, address _to, string memory _old, string memory _new, uint256 _version, string memory _unique_digital_id, uint256 _amount, bool _all, uint256 _units, string memory _payload, uint256 _time) public {
        require(exists_nfts[_unique_digital_id] == true, "NFT does not exist!");
        if(_all){
            uint256 balance = balanceOfUnits(_from, match_nfts[_unique_digital_id]);
            emit Transfer_of_Ownership(_from, _to, _version, _unique_digital_id, _old, _new, _payload, _time, balance);
            safeTransferFrom(_from, _to, match_nfts[_unique_digital_id], _amount, _all, 0, "");
        }
        else{
            safeTransferFrom(_from, _to, match_nfts[_unique_digital_id], _amount, _all, _units, "");
            emit Transfer_of_Ownership(_from, _to, _version, _unique_digital_id, _old, _new, _payload, _time, _units);
        }
        
    }

    function uniquenessChecked(uint256 _version, string memory _unique_digital_id, string memory _owner_id, string memory _fingerprint_method, string memory _fingerprint, string memory _payload, uint256 _time) public {
        require(exists_nfts[_unique_digital_id] == false, "NFT exists!");
        emit Uniqueness_of_Unique_Digital(_version, _unique_digital_id, _owner_id, _fingerprint_method, _fingerprint, _payload, _time);
    }

    function presentationCreated(uint256 _version, string memory _unique_digital_id, string memory _owner_id, string memory _token_method, string memory _token, string memory _payload, uint256 _time) public {
        require(exists_nfts[_unique_digital_id] == true, "NFT does not exist!");
        uint256 balance;
        balance = balanceOf(msg.sender, match_nfts[_unique_digital_id]);
        require(balance > 0, "Do not have right for this NFT, you have no units!");
        emit Presentation_of_Unique_Digital(_version, _unique_digital_id, _owner_id, _token_method, _token, _payload, _time);
    }

    function setApproval(address _operator, bool _approved) public {
        setApprovalForAll(_operator, _approved);
    }

    function deleteUD(uint256 _version, string memory _owner_id, string memory _unique_digital_id, uint256 _amount, uint256 _units, uint256 _time, bool _all, string memory _payload) public{
        require(exists_nfts[_unique_digital_id] == true, "NFT does not exist!");
        if(_all){
            uint256 balance = balanceOfUnits(msg.sender, match_nfts[_unique_digital_id]);
            _burn(msg.sender, match_nfts[_unique_digital_id], _amount, _units, _all);
            emit Delete_Unique_Digital(_version, _unique_digital_id, _owner_id, balance, _time, _payload);
        }
        else{
            _burn(msg.sender, match_nfts[_unique_digital_id], _amount, _units, _all);
            emit Delete_Unique_Digital(_version, _unique_digital_id, _owner_id, _units, _time, _payload);
        }
    }
}

