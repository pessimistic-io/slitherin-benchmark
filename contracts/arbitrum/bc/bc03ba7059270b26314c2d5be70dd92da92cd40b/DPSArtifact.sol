//SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./AccessControlEnumerable.sol";
import "./ERC1155.sol";
import "./IERC721.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./DPSStructs.sol";

contract DPSArtifact is ERC1155, AccessControlEnumerable, Ownable {
    using Strings for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    string private baseURI = "https://damnedpiratessociety.io/api/tokens/";
    string public name = "DPS Artifact";
    string public symbol = "DPSArtifact";

    event LockedUrl();  
    event UrlChanged(uint256 indexed _id, string newUrl);
    event TokenRecovered(address indexed _token, address _destination, uint256 _amount);

    constructor() ERC1155("") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(BURNER_ROLE, _msgSender());
    }

    function mint(
        address _owner,
        uint256 _type,
        uint256 _amount
    ) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "Does not have role MINTER_ROLE");
        _mint(_owner, _type, _amount, "");
    }

    function burn(
        address _from,
        uint256 _type,
        uint256 _amount
    ) external {
        require(hasRole(BURNER_ROLE, _msgSender()), "Does not have role BURNER_ROLE");
        _burn(_from, _type, _amount);
    }

    /**
     * @notice sets baseURI
     * @param _newURI the new base uri
     */
    function setBaseUri(string calldata _newURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = _newURI;
    }

    //****** PUBLIC *******/

    function uri(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(baseURI, id.toString()));
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155, AccessControlEnumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @notice Recover NFT sent by mistake to the contract
     * @param _nft the NFT address
     * @param _destination where to send the NFT
     * @param _tokenId the token to want to recover
     */
    function recoverNFT(
        address _nft,
        address _destination,
        uint256 _tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_destination != address(0), "Destination can not be address 0");
        IERC721(_nft).safeTransferFrom(address(this), _destination, _tokenId);
        emit TokenRecovered(_nft, _destination, _tokenId);
    }

    /**
     * @notice Recover TOKENS sent by mistake to the contract
     * @param _token the TOKEN address
     * @param _destination where to send the NFT
     */
    function recoverERC20(address _token, address _destination) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_destination != address(0), "Destination can not be address 0");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_destination, amount);
        emit TokenRecovered(_token, _destination, amount);
    }
}

