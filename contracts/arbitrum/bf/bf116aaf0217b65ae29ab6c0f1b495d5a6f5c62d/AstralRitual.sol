pragma solidity ^0.8.0;

import "./console.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC721Receiver.sol";

interface IArcane {
    function renounceWizard(uint256 _wizId, address _caller) external;
    function balanceOf(address owner) external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function ownerOf(uint256 _realmId) external view returns (address owner);
    function isApprovedForAll(address owner, address operator)
    external
    returns (bool);
    function safeTransferFrom(
    address from,
    address to,
    uint256 tokenId
    ) external;
}

interface IItems{
    function mintItems(address _to, uint256[] memory _itemIds, uint256[] memory _amounts) external;
}

contract AstralRitual is IERC721Receiver, Ownable, ReentrancyGuard {

    struct Staker {
        address staker;
        uint256 stakedTime;
    }

    IArcane private ARCANE;
    IItems private ITEMS;

    mapping (uint256 => Staker) public stakers;
    uint256 public ritualTime;

    event EnteredRitual(uint256 wizId);

    function beginRitual (uint256 _wizId) external nonReentrant {
        Staker storage staker = stakers[_wizId];
        staker.staker = msg.sender;
        staker.stakedTime = block.timestamp;
        stakers[_wizId] = staker;
        
        ARCANE.safeTransferFrom(msg.sender, address(this), _wizId);

        emit EnteredRitual(_wizId);
    }

    function redeem (uint256 _wizId) external nonReentrant {
        require(msg.sender == stakers[_wizId].staker, "You do not own this wizard");
        if(block.timestamp-stakers[_wizId].stakedTime < ritualTime){
            // send wiz back
            ARCANE.safeTransferFrom(address(this), msg.sender, _wizId);
            stakers[_wizId].staker = address(0x0);
        }else{
            ARCANE.renounceWizard(_wizId, address(this));
            uint256[] memory ids = new uint256[](1);
            ids[0]=1480;
            uint256[] memory amounts = new uint256[](1);
            amounts[0]=1;
            ITEMS.mintItems(msg.sender, ids, amounts);
            stakers[_wizId].staker = address(0x0);
        }
        console.log("time elapsed ",block.timestamp-stakers[_wizId].stakedTime < ritualTime);

    }

    function getTimeLeft(uint256 _wizId) external view returns(uint256) {
        return block.timestamp-stakers[_wizId].stakedTime;
    }

    // function getStaked(address _owner) external view returns(address[] memory, uint256[] memory){
    //     uint256 balance = ARCANE.balanceOf(address(this));
    //     address[] memory addresses = new address[](balance);
    //     // uint256[] memory wizIds = new uint256[](balance);

    //     for(uint i=0;i<balance;i++){
    //         uint256 wizId = ARCANE.tokenOfOwnerByIndex(address(this), i);
    //         if(stakers[wizId].staker == _owner){

    //         }
    //         addresses[i]=stakers[wizIds[i]].staker;
    //     }
    //     return (addresses,wizIds);
    // }

    function getStakers() external view returns(address[] memory, uint256[] memory){
        uint256 balance = ARCANE.balanceOf(address(this));
        address[] memory addresses = new address[](balance);
        uint256[] memory wizIds = new uint256[](balance);

        for(uint i=0;i<balance;i++){
            wizIds[i]= ARCANE.tokenOfOwnerByIndex(address(this), i);
            addresses[i]=stakers[wizIds[i]].staker;
        }
        return (addresses,wizIds);
    }

    function onERC721Received(
        address,
        address, 
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function setArcane (address _arcaneAddress) external onlyOwner{
        ARCANE= IArcane(_arcaneAddress);
    }

    function setItems (address _itemsAddress) external onlyOwner{
        ITEMS= IItems(_itemsAddress);
    }

    function setRitualTime(uint256 _time) external onlyOwner{
        ritualTime = _time;
    }
}
