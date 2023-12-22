// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./ERC165.sol";

import "./IHunterValidator.sol";
import "./IHuntGame.sol";

contract ERC721Whitelist is ERC165, IHunterValidator {
    /// huntGame=>erc721
    mapping(address => address) whitelist;
    IHuntNFTFactory factory;

    constructor(IHuntNFTFactory _factory) {
        factory = _factory;
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == IHunterValidator.huntGameRegister.selector ||
            interfaceId == IHunterValidator.isHunterPermitted.selector ||
            interfaceId == IHunterValidator.validateHunter.selector ||
            ERC165.supportsInterface(interfaceId);
    }

    function huntGameRegister() public {
        bytes memory params = factory.tempValidatorParams();
        require(params.length == 20, "PARAMS_ERR");
        assert(whitelist[msg.sender] == address(0));
        whitelist[msg.sender] = address(bytes20(params));
    }

    function isHunterPermitted(
        address _game,
        address,
        address _hunter,
        uint64,
        bytes calldata
    ) public view returns (bool) {
        address _nft = whitelist[_game];
        if (_nft == address(0)) {
            revert("NO_NFT_REGISTER");
        }
        return IERC721(_nft).balanceOf(_hunter) > 0;
    }

    function validateHunter(
        address _game,
        address _sender,
        address _hunter,
        uint64 _bullet,
        bytes calldata _payload
    ) public view {
        require(isHunterPermitted(_game, _sender, _hunter, _bullet, _payload), "INVALID_HUNTER");
    }
}

