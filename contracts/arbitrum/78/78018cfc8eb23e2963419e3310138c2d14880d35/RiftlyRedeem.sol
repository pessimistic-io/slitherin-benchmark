// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import {Initializable} from "./Initializable.sol";
import {AccessControlEnumerableUpgradeable, IAccessControlEnumerableUpgradeable} from "./AccessControlEnumerableUpgradeable.sol";

import {IERC165Upgradeable} from "./IERC165Upgradeable.sol";
import {ECDSAUpgradeable} from "./ECDSAUpgradeable.sol";
import {EIP712Upgradeable} from "./draft-EIP712Upgradeable.sol";
// import {LicenseVersion, CantBeEvilUpgradable} from "./CantBeEvilUpgradable.sol";
import { IERC721Enumerable } from "./IERC721Enumerable.sol";
import {EnumerableSetUpgradeable} from "./EnumerableSetUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";

import { IERC721AQueryable } from "./IERC721AQueryable.sol";

import { IERC1155 } from "./IERC1155.sol";

contract RiftlyRedeem is
    Initializable,
    AccessControlEnumerableUpgradeable
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    event Redeemed(address tokenContract, address receiver, uint256 slotId);

    /// @dev Emit an event when the contract is deployed
    event ContractDeployed(address owner);

    bytes32 public constant REDEEMABLE_ROLE = keccak256("REDEEMABLE_ROLE");
    address private _treasury;

    EnumerableSetUpgradeable.AddressSet private _approvalCollections;

    bool public isPaused;

    function initialize(address treasury_) external initializer {
     
        __AccessControlEnumerable_init();
        // __CantBeEvil_init(LicenseVersion.PUBLIC);
    
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        isPaused=false;
        _treasury=address(treasury_); 
        emit ContractDeployed(_msgSender());
    }

    function redeemERC20(address _tokenContract, address _receiver, uint256 _amount, uint256 _slotId) external onlyRole(REDEEMABLE_ROLE)
    {
        require(
            isPaused == false,
            "Paused"
        );
        require(
            IERC20(_tokenContract).balanceOf(_treasury) >= _amount,
            "Treasury out of funds"
        );   
        require(
            IERC20(_tokenContract).allowance(_treasury, address(this)) >= _amount,
            "Allowance insufficient"
        );   
        require(IERC20(_tokenContract).transferFrom(_treasury, _receiver, _amount));

        emit Redeemed(
            _tokenContract,
            _receiver,
            _slotId
        );
    }

    function redeemERC721(address _nftContract, address _receiver, uint256 _slotId) external onlyRole(REDEEMABLE_ROLE)
    {
        require(
            isPaused == false,
            "Paused"
        );
        require(
            IERC721Enumerable(_nftContract).balanceOf(_treasury) >= 1,
            "Treasury out of nft"
        ); 

        uint256 _tokenId = IERC721Enumerable(_nftContract).tokenOfOwnerByIndex(_treasury, 0);

        IERC721Enumerable(_nftContract).transferFrom(_treasury, _receiver, _tokenId);

        emit Redeemed(
            _nftContract,
            _receiver,
            _slotId
        );
    }
    

    function redeemERC721A(address _nftContract, address _receiver, uint256 _slotId) external onlyRole(REDEEMABLE_ROLE)
    {
        require(
            isPaused == false,
            "Paused"
        );
        require(
            IERC721AQueryable(_nftContract).balanceOf(_treasury) >= 1,
            "Treasury out of nft"
        ); 

        uint256[] memory _tokens = IERC721AQueryable(_nftContract).tokensOfOwner(_treasury);

        uint256 _tokenId = _tokens[0];

        IERC721AQueryable(_nftContract).transferFrom(_treasury, _receiver, _tokenId);

        emit Redeemed(
            _nftContract,
            _receiver,
            _slotId
        );
    }

    function redeemERC1155(address _contract, address _receiver, uint256 _tokenId, uint256 _slotId) external onlyRole(REDEEMABLE_ROLE)
    {
        require(
            isPaused == false,
            "Paused"
        );
        require(
            IERC1155(_contract).balanceOf(_treasury, _tokenId) >= 1,
            "Treasury out of nft"
        ); 

        IERC1155(_contract).safeTransferFrom(_treasury, _receiver, _tokenId, 1, "");

        emit Redeemed(
            _contract,
            _receiver,
            _slotId
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(
            AccessControlEnumerableUpgradeable
            // CantBeEvilUpgradable
            // ,IERC165Upgradeable
        )
        returns (bool)
    {
        return
            type(IAccessControlEnumerableUpgradeable).interfaceId ==
            interfaceId ||
            // CantBeEvilUpgradable.supportsInterface(interfaceId) ||
            super.supportsInterface(interfaceId);
    }


    /**
    @notice Change status of isPaused, to pause all minting functions
    @param _isPaused boolean to pause
    */
    function setContractPaused(bool _isPaused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isPaused = _isPaused;
        // emit UpdatedPauseContract(_isPaused, msg.sender);
    }

      function addCollection(address _collection) external {
        _approvalCollections.add(_collection);
    }

    // @notice the underlying internal _add function already check if the set contains the _collection
    function removeCollection(address _collection) external {
        _approvalCollections.remove(_collection);
    }

    function getApprovalCollections() external view returns (address[] memory) {
        return _approvalCollections.values();
    }

    function testERC721BalanceOf(address _nftContract) external view returns (uint256) {
            return IERC721Enumerable(_nftContract).balanceOf(_treasury);
    }

    function testERC721ATokensOfOwner(address _nftContract) external view returns (uint256[] memory) {
            return IERC721AQueryable(_nftContract).tokensOfOwner(_treasury);
    }

        function getTreasury() external view returns (address) {
        return _treasury;
    }
}
