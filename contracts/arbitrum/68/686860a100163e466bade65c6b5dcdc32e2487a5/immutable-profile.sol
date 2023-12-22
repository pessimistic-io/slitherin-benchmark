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

    // Function to set or update username
    function setUsername(string memory _username) public {
        require(!users[msg.sender].blocked, "User is blocked");

        _setUsername(msg.sender, _username);
    }

    // Function to set or update user NFT
    function setUserNFT(address _nftAddress, uint256 _tokenId) public {
        require(!users[msg.sender].blocked, "User is blocked");

        _setUserNFT(msg.sender, _nftAddress, _tokenId);
    }

    // Function for the owner to set or update user data
    function setUserDataByOwner(
        address _userAddress,
        string memory _username,
        address _nftAddress,
        uint256 _tokenId
    ) public onlyOwner {
        _setUsername(_userAddress, _username);
        _setUserNFT(_userAddress, _nftAddress, _tokenId);
    }

    // Internal function to set or update username
    function _setUsername(
        address _userAddress,
        string memory _username
    ) internal {
        if (bytes(users[_userAddress].username).length == 0) {
            userAddresses.push(_userAddress);
        }

        users[_userAddress].username = _username;

        emit UserDataUpdated(
            _userAddress,
            _username,
            users[_userAddress].nftAddress,
            users[_userAddress].tokenID
        );
    }

    // Internal function to set or update user NFT
    function _setUserNFT(
        address _userAddress,
        address _nftAddress,
        uint256 _tokenId
    ) internal {
        if (!(_nftAddress == address(0))) {
            require(
                IERC721(_nftAddress).supportsInterface(
                    type(IERC721).interfaceId
                ),
                "Invalid ERC721 contract address"
            );
        }

        if (msg.sender != owner()) {
            require(
                msg.sender == _userAddress,
                "Only owner can update data for other users"
            );
        }

        if (msg.sender != owner()) {
            require(
                IERC721(_nftAddress).ownerOf(_tokenId) == msg.sender,
                "Caller must be the NFT owner"
            );
        }

        users[_userAddress].nftAddress = _nftAddress;
        users[_userAddress].tokenID = _tokenId;

        emit UserDataUpdated(
            _userAddress,
            users[_userAddress].username,
            _nftAddress,
            _tokenId
        );
    }

    // Function to get user data
    function getUserData(
        address _userAddress
    ) public view returns (string memory, address, bool, uint256) {
        User storage user = users[_userAddress];
        return (user.username, user.nftAddress, user.blocked, user.tokenID);
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

