// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./AccessControlEnumerable.sol";
import "./IBEERC721.sol";

contract NftDistributor is AccessControlEnumerable {
  bytes32 public constant MANAGE_ROLE = keccak256("MANAGE_ROLE");

  // user address => nft ids
  mapping(address => uint256[]) public ownerToNFTs;
  // nft id => minted
  mapping(uint256 => bool) public nftMinted;

  IBEERC721 public nft;

  // NFT distributor open status
  bool public isOpen = false;

  event Minted(
    address indexed user,
    address indexed nft,
    uint256[] nftSIds,
    uint256[] nftTIds
  );

  event OpenStatusChange(bool indexed open);

  /**
   * @dev Contract constructor.
   *
   * Initializes the contract with the specified addresses and sets the admin and management roles.
   *
   * Parameters:
   * - _nftTarget: The address of NFT that will be minted by this contract. Need MINTER_ROLE
   * - _nftSource: The address of the source NFT that will check if user has mint permission.
   * - _manageAddress: The address that will have the MANAGE_ROLE assigned.
   */
  constructor(address _nftTarget, address[] memory _manageAddress) {
    // Set up the ADMIN_ROLE and MANAGE_ROLE
    _setRoleAdmin(MANAGE_ROLE, DEFAULT_ADMIN_ROLE);

    // Grant the ADMIN_ROLE to the deployer and to the contract itself
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

    // Grant the MANAGE_ROLE to the specified address
    for (uint256 i = 0; i < _manageAddress.length; ++i) {
      _setupRole(MANAGE_ROLE, _manageAddress[i]);
    }

    // Initialize the nft contract with IBEERC721 interface
    nft = IBEERC721(_nftTarget);
  }

  /**
   * @dev Modifier that checks if the caller has the MANAGE_ROLE.
   *
   * The function uses the _checkRole() function from the AccessControl library.
   * If the check is successful, the code defined by the function that uses this modifier is executed.
   */
  modifier onlyManager() {
    // Check if the caller has the MANAGE_ROLE
    _checkRole(MANAGE_ROLE, _msgSender());
    // If the check is successful, execute the code in the function that uses this modifier
    _;
  }

  function updateOpenStatus(bool _open) external onlyManager {
    require(isOpen != _open, "Open status is same");
    isOpen = _open;
    emit OpenStatusChange(_open);
  }

  function mintNft(uint256 count) external {
    require(isOpen, "NFT distributor is not open");
    require(count > 0, "Count is zero");
    address _user = _msgSender();
    // Check that there are enough mintable NFTs
    require(count <= getMintableCount(_user), "Mintable count is not enough");
    // Get the array of the user's owned NFTs
    uint256[] memory nfts = ownerToNFTs[_user];
    // Initialize variables
    uint256 index = 0;
    uint256[] memory nftSource = new uint256[](count);

    // Loop through the user's owned NFTs
    for (uint256 i = 0; i < nfts.length; i++) {
      uint256 nftSId = nfts[i];
      // Check if the NFT is mintable
      if (!nftMinted[nftSId] && index < count) {
        // Add the NFT's source ID to the list of sources
        nftSource[index] = nftSId;
        nftMinted[nftSId] = true;
        // Mint the NFT to the user's address
        index++;
      }
    }
    uint256[] memory _nftIds = nft.batchMint(_user, count);
    // Emit event with details of the minting operation
    emit Minted(_user, address(nft), nftSource, _nftIds);
  }

  /**
   * @dev The addNFTData function adds an array of NFT IDs to the list of NFT IDs owned by a user.
   *      mintToUser method would check if target user had permission to mint NFTs.
   *
   * Only functions called by an address with the MANAGE_ROLE permission can access this function.
   * The function takes in the address of the user and an array of NFT IDs. It then loops through the array
   * of NFT IDs, and adds each one to the end of the array of NFTs owned by that user to update their ownership data.
   *
   * @param _user - The address of the user being updated with new NFT data
   * @param _nftIds - An array of NFT IDs being added to the user's NFT data
   */
  function addNFTData(
    address _user,
    uint256[] calldata _nftIds
  ) external onlyManager {
    // Loop through the array of NFT IDs
    for (uint256 i = 0; i < _nftIds.length; i++) {
      // Add each NFT ID to the end of the array of NFTs owned by the user
      ownerToNFTs[_user].push(_nftIds[i]);
    }
  }

  /**
   * @dev The getMintableCount function gets the number of NFTs owned by a user that have not yet been minted.
   *
   * This is a read-only function, meaning it doesn't modify the state of the blockchain.
   * It takes in the address of the user whose mintable count is being determined,
   * and returns the number of NFTs owned by the user that have not yet been minted.
   *
   * @param _user - The address of the user whose mintable count is being determined
   * @return count - The number of NFTs owned by the user that have not yet been minted
   */
  function getMintableCount(address _user) public view returns (uint256) {
    // Get an array of all NFT IDs owned by the user
    uint256[] memory nfts = ownerToNFTs[_user];
    // Initialize count to zero
    uint256 count = 0;
    // Loop through the array of NFT IDs
    for (uint256 i = 0; i < nfts.length; i++) {
      // Get the NFT ID at this index of the loop
      uint256 nftAId = nfts[i];
      // Check if the NFT has not yet been minted
      if (!nftMinted[nftAId]) {
        // If the NFT has not yet been minted, increment the mintable count
        count++;
      }
    }
    // Return the final mintable count
    return count;
  }

  /**
   * @dev The getMintableNftIds function gets an array of NFT IDs owned by a user that have not yet been minted.
   *
   * This is a read-only function, meaning it doesn't modify the state of the blockchain.
   * It takes in the address of the user whose mintable NFT IDs are being determined,
   * and returns an array of the NFT IDs owned by the user that have not yet been minted.
   *
   * @param _user - The address of the user whose mintable NFT IDs are being determined
   * @return mintableNftIds - An array of the NFT IDs owned by the user that have not yet been minted
   */
  function getMintableNftIds(
    address _user
  ) external view returns (uint256[] memory) {
    // Get an array of all NFT IDs owned by the user
    uint256[] memory nfts = ownerToNFTs[_user];
    // Initialize an array for mintable NFT IDs with the same length as the array of all NFT IDs
    uint256[] memory mintableNftIds = new uint256[](nfts.length);
    // Initialize an index counter to zero
    uint256 index = 0;
    // Loop through the array of NFT IDs
    for (uint256 i = 0; i < nfts.length; i++) {
      // Get the NFT ID at this index of the loop
      uint256 nftId = nfts[i];
      // Check if the NFT has not yet been minted
      if (!nftMinted[nftId]) {
        // If the NFT has not yet been minted, add it to the mintable NFT IDs array
        mintableNftIds[index] = nftId;
        // Increment the index counter
        index++;
      }
    }
    // Return the array of mintable NFT IDs
    return mintableNftIds;
  }
}

