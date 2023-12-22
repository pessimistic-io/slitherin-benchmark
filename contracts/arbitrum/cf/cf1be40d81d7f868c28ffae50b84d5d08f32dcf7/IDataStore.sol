interface DS {
    function getAddress(string calldata key) external view returns (address);

    function setAddress(string calldata key, address value, bool overwrite) external returns (bool);
}

