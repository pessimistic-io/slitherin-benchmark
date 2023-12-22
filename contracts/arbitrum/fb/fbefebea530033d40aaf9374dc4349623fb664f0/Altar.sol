pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC1155Receiver.sol";

interface IAdventure {
    function levelUpFromAltar(uint256 _wizId, uint256 _newLevel) external;
}

interface ISender{
     function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(
            address from,
            address to,
            uint256 tokenId
        ) external;
}

// Ascend to level up your Wizard
contract Altar is Ownable, IERC1155Receiver {

    event LevelUp(
        uint256 wizId,
        uint256 levelToPass
    );

    mapping (uint256 => mapping (uint256  => bool)) public canLevelUp;
    mapping (uint256 => address) public itemAddress;
    mapping (uint256 => uint256) public itemId;

    IAdventure public ADVENTURE;

    // adventure authorises the level up
    function authoriseLevelUp (uint256 _wizId, uint256 _lvl) external {
        require(msg.sender==address(ADVENTURE), "You don't have permission for this");
        canLevelUp[_wizId][_lvl] = true;

    }


    // user goes ahead and levels up
    function levelUp(uint256 _wizId, uint256 _levelToPass) external{
        require(canLevelUp[_wizId][_levelToPass], "You cannot level up yet.");
        ISender requiredAddress = ISender(itemAddress[_levelToPass]);
        uint256 requiredId = itemId[_levelToPass];

        requiredAddress.safeTransferFrom(msg.sender, address(this), requiredId);

        // level up
        ADVENTURE.levelUpFromAltar(_wizId,_levelToPass);

        emit LevelUp(_wizId, _levelToPass);

    }

    function setAdventure(address _adventure) external onlyOwner {
        ADVENTURE = IAdventure(_adventure);
    }

    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool){

    }

}
