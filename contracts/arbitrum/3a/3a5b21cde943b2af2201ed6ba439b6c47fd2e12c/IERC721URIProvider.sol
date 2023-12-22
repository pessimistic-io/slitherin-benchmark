pragma solidity >0.8.0;

interface IERC721URIProvider {
    function baseURI() external view returns (string memory);

    function updateBaseURI(string memory baseURI) external;
}

