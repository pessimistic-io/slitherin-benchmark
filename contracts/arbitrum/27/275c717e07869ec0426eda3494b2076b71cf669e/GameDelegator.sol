// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./ERC165.sol";

import "./IHunterValidator.sol";
import "./IHuntGame.sol";

contract GameDelegator is Ownable, ERC165, IHunterValidator {
    mapping(address => bool) public isDelegator;

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == IHunterValidator.huntGameRegister.selector ||
            interfaceId == IHunterValidator.isHunterPermitted.selector ||
            interfaceId == IHunterValidator.validateHunter.selector ||
            ERC165.supportsInterface(interfaceId);
    }

    function huntGameRegister() external {}

    function validateHunter(
        address _game,
        address _sender,
        address _hunter,
        uint64 _bullet,
        bytes calldata _payload
    ) public view {
        require(isHunterPermitted(_game, _sender, _hunter, _bullet, _payload), "only delegator");
    }

    function isHunterPermitted(address, address _sender, address, uint64, bytes calldata) public view returns (bool) {
        return isDelegator[_sender];
    }

    /// only owner
    function enableDelegator(address delegator, bool enabled) public onlyOwner {
        isDelegator[delegator] = enabled;
    }
}

