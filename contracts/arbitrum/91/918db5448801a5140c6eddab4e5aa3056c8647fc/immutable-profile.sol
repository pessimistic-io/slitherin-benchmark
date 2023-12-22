// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./Ownable.sol";

contract ImmutableProfile is Ownable {
    // User struct to store username and NFT address
    struct User {
        string username;
        address nftAddress;
        uint256 tokenID;
        bool blocked;
    }

    // Mapping to store user data, using their Ethereum address as a key
    mapping(address => User) private users;

    // Array to store the Ethereum addresses of registered users
    address[] private userAddresses;

    // Event that is fired when user data is updated
    event UserDataUpdated(
        address indexed userAddress,
        string username,
        address indexed nftAddress,
        uint256 indexed tokenID
    );

    // Function to set or update user data
    function setUserData(string memory _username, address _nftAddress, uint256 _tokenId) public {
        require(!users[msg.sender].blocked, "User is blocked");

        _setUserData(msg.sender, _username, _nftAddress, _tokenId);
    }

    // Function for the owner to set or update user data
    function setUserDataByOwner(
        address _userAddress,
        string memory _username,
        address _nftAddress,
        uint256 _tokenId
    ) public onlyOwner {
        _setUserData(_userAddress, _username, _nftAddress, _tokenId);
    }

    // Internal function to set or update user data
    function _setUserData(
        address _userAddress,
        string memory _username,
        address _nftAddress,
        uint256 _tokenId
    ) internal {
        if(!(_nftAddress == address(0))){
        // Check if the given NFT address is a valid ERC721 contract
            require(
                IERC721(_nftAddress).supportsInterface(type(IERC721).interfaceId),
                "Invalid ERC721 contract address"
            );
        }

        // When called by non-owner, ensure that the caller can only update their own data
        if (msg.sender != owner()) {
            require(
                msg.sender == _userAddress,
                "Only owner can update data for other users"
            );
        }

         if (msg.sender != owner()) {
            require(IERC721(_nftAddress).ownerOf(_tokenId) == msg.sender, "Caller must be the NFT owner");
        }

        // If user not registered, add their address to the userAddresses array
        if (bytes(users[_userAddress].username).length == 0) {
            userAddresses.push(_userAddress);
        }

        // Update user data in the mapping
        users[_userAddress] = User(
            _username,
            _nftAddress,
            _tokenId,
            users[_userAddress].blocked
        );

        // Emit the event with updated user data
        emit UserDataUpdated(_userAddress, _username, _nftAddress, _tokenId);
    }

    // Function to get user data
    function getUserData(
        address _userAddress
    ) public view returns (string memory, address, bool) {
        User storage user = users[_userAddress];
        return (user.username, user.nftAddress, user.blocked);
    }

    // Function for the owner to block a user and reset their profile
    function blockAndResetUserProfile(address _userAddress) public onlyOwner {
        users[_userAddress] = User("", address(0), 0, true);
    }

    // Function to get all user profiles with pagination (100 profiles per page)
    function getUserProfiles(
        uint256 _page
    ) public view returns (User[] memory) {
        uint256 startIndex = _page * 100;
        uint256 endIndex = startIndex + 100;

        // If the startIndex is greater than or equal to the userAddresses length, return an empty array
        if (startIndex >= userAddresses.length) {
            return new User[](0);
        }

        // If endIndex is greater than the userAddresses length, set endIndex to the length
        if (endIndex > userAddresses.length) {
            endIndex = userAddresses.length;
        }

        // Calculate the size of the result array and create a new array of User structs
        uint256 resultSize = endIndex - startIndex;
        User[] memory result = new User[](resultSize);

        // Iterate through the userAddresses array from startIndex to endIndex and populate the result array
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = users[userAddresses[i]];
        }

        return result;
    }
}

