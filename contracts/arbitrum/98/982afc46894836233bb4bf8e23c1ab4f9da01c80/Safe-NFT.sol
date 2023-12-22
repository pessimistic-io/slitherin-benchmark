// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./IERC721.sol";

contract Enum {
    enum Operation {
        Call,
        DelegateCall
    }
    enum UnlockOption {
        NONE,
        UNLOCK_ACCOUNT,
        UNLOCK_TIME
    }
}

interface GnosisSafe {
    function getOwners() external view returns (address[] memory);

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success);
}

contract SafeNFT {
    address internal constant SENTINEL_ADDRESS = address(0x1);
    struct Safe {
        uint256 id;
        address safe;
        Enum.UnlockOption unlockOption;
        address unlockAddress;
        uint256 unlockTime;     
    }

    struct SafeOfAnNft {
        uint256 nftId;
        uint256 totalSafe;
        Safe[] safes;
    }
    uint256 public constant version = 1;
    mapping(address => mapping(uint256 => SafeOfAnNft)) private safesOfAnNft;

    event Attach(
        address indexed _nftContract,
        uint256 indexed _tokenId,
        address _safeAddress
    );
    event Detach(
        address indexed _nftContract,
        uint256 indexed _tokenId,
        address _safeAddress
    );
 
    constructor() {}

    // function allows it to check if it is the only owner of the safe at address x. If yes, stores Safe address in array. Returns boolean.
    /// @param _safeAddress Gnosis safe address.
    function ownsSafe(address _safeAddress)
        public
        view
        returns (address[] memory)
    {
        GnosisSafe _currentSafe = GnosisSafe(payable(_safeAddress));
        address[] memory currentSafeOwners = _currentSafe.getOwners();
        return currentSafeOwners;
    }

    /// @dev Function get list attached Safe to an NFT at _nftContract address
    /// @param _nftContract nft contract address.
    /// @param _tokenId token ID.
    function getSafesOfAnNft(address _nftContract, uint256 _tokenId)
        public
        view
        returns (SafeOfAnNft memory)
    {
        return safesOfAnNft[_nftContract][_tokenId];
    }

    /// @dev Function attach Safe to an NFT at _nftContract address
    /// @param _nftContract nft contract address.
    /// @param _tokenId token ID.
    /// @param _safeAddress safe address.
    /// @param _unlockOption unlock option.
    /// @param _unlockAddress the address that who will unlock the Safe if _unlockOption is UNLOCK_ACCOUNT option.
    /// @param _unlockTime time that nft owner can unlock the Safe after that time if _unlockOption is UNLOCK_TIME option.
    function attachSafe(
        address _nftContract,
        uint256 _tokenId,
        address _safeAddress,
        Enum.UnlockOption _unlockOption,
        address _unlockAddress, 
        uint256 _unlockTime 
    ) public {
        SafeOfAnNft storage currentSafes = safesOfAnNft[_nftContract][_tokenId];
        for (uint256 i = 0; i < currentSafes.safes.length; i++) {
            if (_safeAddress == currentSafes.safes[i].safe) {
                revert("SAFE_ALREADY_ATTACHED");
            }
        }
        uint256 totalSafe = currentSafes.totalSafe + 1;
        currentSafes.nftId = _tokenId;
        currentSafes.totalSafe = totalSafe;
        currentSafes.safes.push(Safe(totalSafe, _safeAddress, _unlockOption, _unlockAddress, _unlockTime));
        emit Attach(_nftContract, _tokenId, _safeAddress);
    }
 
    /// @dev function reveals the address that owns this contract.  It will be the address that owns the NFT in ownerNFT() function. Returns address.
    /// @param _nftContract nft contract address.
    /// @param _tokenId token ID.
    function ownerAddress(address _nftContract, uint256 _tokenId)
        public
        view
        returns (address)
    {
        IERC721 erc721 = IERC721(_nftContract);
        return erc721.ownerOf(_tokenId);
    }

    /// @dev function return index in array
    /// @param arr Array need to check.
    /// @param searchFor index.
    function indexOf(address[] memory arr, address searchFor)
        private
        pure
        returns (uint256)
    {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] == searchFor) {
                return i;
            }
        }
        revert("OLD_OWNER_NOT_FOUND");
    }

    /// @dev function detach Gnosis-safe
    /// @param _nftContract nft contract address.
    /// @param _tokenId token ID.
    /// @param _safeId safe ID.
    /// @param _safeAddress safe address.
    function destroy(
        address _nftContract,
        uint256 _tokenId,
        uint256 _safeId,
        address _safeAddress
    ) public {
        require(
            ownerAddress(_nftContract, _tokenId) == msg.sender,
            "ONLY_OWNER_DO_THIS_ACTION"
        );

        address[] memory safeOwners = ownsSafe(_safeAddress);

        uint256 indexOfOldOwner = indexOf(safeOwners, address(this));
        address prevOwnerAddress = SENTINEL_ADDRESS;
        if (safeOwners.length > 1) {
            prevOwnerAddress = safeOwners[indexOfOldOwner - 1];
        }
       
        SafeOfAnNft storage currentSafes = safesOfAnNft[_nftContract][_tokenId];
        require(_tokenId == currentSafes.nftId, "INVALID_ID");
        Safe memory removeSafe;
        for (uint256 i = 0; i < currentSafes.safes.length; i++) {
            if (
                _safeId == currentSafes.safes[i].id &&
                _safeAddress == currentSafes.safes[i].safe
            ) {
                if (currentSafes.safes[i].unlockOption == Enum.UnlockOption.UNLOCK_ACCOUNT) {
                    require(currentSafes.safes[i].unlockAddress == ownerAddress(_nftContract, _tokenId), "INVALID_OWNER");
                }
                if (currentSafes.safes[i].unlockOption == Enum.UnlockOption.UNLOCK_TIME) {
                    require(currentSafes.safes[i].unlockTime <= block.timestamp, "NOT_START_YET");
                }
                removeSafe = currentSafes.safes[i];
                currentSafes.safes[i] = currentSafes.safes[
                    currentSafes.safes.length - 1
                ];
                currentSafes.safes[currentSafes.safes.length - 1] = removeSafe;
                break;
            }
        }
        currentSafes.safes.pop();
        bytes memory data = abi.encodeWithSignature(
            "swapOwner(address,address,address)",
            prevOwnerAddress,
            address(this),
            msg.sender
        );
        emit Detach(_nftContract, _tokenId, _safeAddress);
        bool success = GnosisSafe(_safeAddress).execTransactionFromModule(
            address(_safeAddress),
            0,
            data,
            Enum.Operation.Call
        );
        require(success, "ERROR_EXECUTE_TRANSACTION");
    }
    
    /// @dev function unclock Gnosis-safe
    /// @param _nftContract nft contract address.
    /// @param _tokenId token ID.
    /// @param _safeId safe ID.
    /// @param _safeAddress safe address.
    function unlockSafe(
        address _nftContract,
        uint256 _tokenId,
        uint256 _safeId,
        address _safeAddress
    ) public {
        SafeOfAnNft storage currentSafes = safesOfAnNft[_nftContract][_tokenId];
        for (uint256 i = 0; i < currentSafes.safes.length; i++) {
            if (
                _safeId == currentSafes.safes[i].id &&
                _safeAddress == currentSafes.safes[i].safe
            ) {
               require(currentSafes.safes[i].unlockOption == Enum.UnlockOption.UNLOCK_ACCOUNT, "ONLY_UNLOCK_BY_ADDRESS");
               require(currentSafes.safes[i].unlockAddress == msg.sender, "INVALID_UNLOCK_ADDRESS");
               currentSafes.safes[i].unlockAddress = ownerAddress(_nftContract, _tokenId);
            }
        }
    }
}

