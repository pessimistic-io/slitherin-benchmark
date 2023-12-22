// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

/**

███╗   ███╗ █████╗ ███████╗██╗ █████╗     ███╗   ██╗██╗   ██╗████████╗███████╗
████╗ ████║██╔══██╗██╔════╝██║██╔══██╗    ████╗  ██║██║   ██║╚══██╔══╝██╔════╝
██╔████╔██║███████║█████╗  ██║███████║    ██╔██╗ ██║██║   ██║   ██║   ███████╗
██║╚██╔╝██║██╔══██║██╔══╝  ██║██╔══██║    ██║╚██╗██║██║   ██║   ██║   ╚════██║
██║ ╚═╝ ██║██║  ██║██║     ██║██║  ██║    ██║ ╚████║╚██████╔╝   ██║   ███████║
╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝    ╚═╝  ╚═══╝ ╚═════╝    ╚═╝   ╚══════╝

*/

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { ONFT721, IERC721 } from "./ONFT721.sol";

/**
 * @title MafiaNuts utility smart contract.
 * @author n0ah <https://twitter.com/nftn0ah>
 * @author aster <https://twitter.com/aster2709>
 */
contract MafiaNutsARB is ONFT721 {
    //
    // STORAGE
    //
    string private uri;

    //
    // EVENTS
    //
    event Deploy(address deployer, uint timestamp);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _minGasToTransfer,
        address _lzEndpoint
    ) ONFT721(_name, _symbol, _minGasToTransfer, _lzEndpoint) {
        emit Deploy(msg.sender, block.timestamp);
    }

    /**
     * @notice set uri
     * @dev only owner
     */
    function setURI(string memory _uri) external onlyOwner {
        uri = _uri;
    }

    /**
     * @notice recover stuck erc20 tokens, contact team
     * @dev only owner can call, sends tokens to owner
     */
    function recoverFT(address _token, uint _amount) external onlyOwner {
        IERC20(_token).transfer(owner(), _amount);
    }

    /**
     * @notice recover stuck erc721 tokens, contact team
     * @dev only owner can call, sends tokens to owner
     */
    function recoverNFT(address _token, uint _tokenId) external onlyOwner {
        IERC721(_token).transferFrom(address(this), owner(), _tokenId);
    }

    //
    // OVERRIDES
    //
    function _baseURI() internal view override returns (string memory) {
        return uri;
    }
}

