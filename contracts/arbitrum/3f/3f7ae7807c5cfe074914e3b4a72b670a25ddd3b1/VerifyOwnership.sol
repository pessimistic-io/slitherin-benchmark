pragma solidity ^0.8.0;

import "./Ownable.sol";

struct State {
    address quester;
    uint256 startTime;
    uint256 currX;
    uint256 currY;
    bool reward;
}

interface IArcane {
    function ownerOf(uint256 tokenId) external view returns (address);

    function getWizardInfosIds(
        uint256 _wizId
    ) external view returns (uint256[5] memory);
}

interface IAdventure {
    function states(uint256 tokenId) external view returns (State memory);
}

contract VerifyOwnership is Ownable {
    IArcane public ARCANE;
    IAdventure public ADVENTURE;

    function verify(
        uint256 _wizId,
        address _owner
    ) external view returns (bool) {
        if (
            ARCANE.ownerOf(_wizId) == _owner ||
            ADVENTURE.states(_wizId).quester == _owner
        ) {
            return true;
        } else {
            return false;
        }
    }

    function getWizardInfosIds(
        uint256 _wizId
    ) external view returns (uint256[5] memory) {
        return ARCANE.getWizardInfosIds(_wizId);
    }

    function setConnected(
        address _arcane,
        address _adventure
    ) external onlyOwner {
        ARCANE = IArcane(_arcane);
        ADVENTURE = IAdventure(_adventure);
    }
}

