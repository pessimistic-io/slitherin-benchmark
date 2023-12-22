// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./IERC20.sol";

contract DystoSoul is Initializable, OwnableUpgradeable, ERC721Upgradeable {

    uint256 public price;
    uint256 public lastTokenId;
    bool public paused;
    string public baseURI;
    address public paymentMethod;

    mapping(address => bool) public owners;

    function initialize(
        uint256 _price,
        bool _paused,
        address _paymentMethod
    ) external initializer {
        __ERC721_init("DystoSoul", "DYSTOSOUL");
        __Ownable_init();

        lastTokenId = 0;

        price = _price;
        paused = _paused;
        paymentMethod = _paymentMethod;
    }

    function mint() external payable {
        require(paused == false, "Contract is paused.");
        require(
            owners[msg.sender] == false,
            "This address already minted one DystoSoul NFT Token."
        );

        if(paymentMethod == address(0)) {
            require(msg.value >= price, "Not enough ether to pay.");
        } else {
            IERC20(paymentMethod).transferFrom(msg.sender, address(this), price);
        }

        lastTokenId++;
        _safeMint(msg.sender, lastTokenId);
        owners[msg.sender] = true;
    }

    function mintTeam(address _receiver, uint256 _numTokens) external onlyOwner {
        uint256 i;
        for (; i < _numTokens; i++) {
            lastTokenId++;
            _safeMint(_receiver, lastTokenId);
        }
    }

    function setPrice(uint256 _price) public onlyOwner {
        price = _price;
    }

    function setPaymentMethod(address _paymentMethod) public onlyOwner {
        paymentMethod = _paymentMethod;
    }

    function setPaused(bool _paused) public onlyOwner {
        paused = _paused;
    }

    function withdraw(address _receiver) public onlyOwner {
        uint _balance = address(this).balance;
        require(_balance > 0, "No ether left to withdraw");

        payable(_receiver).transfer(_balance);
    }

    function withdrawERC20(address _tokenContractAddress, address _receiver) public onlyOwner {
        IERC20 _tokenContract = IERC20(_tokenContractAddress);
        uint _balance = _tokenContract.balanceOf(address(this));
        require(_balance > 0, "No tokens left to withdraw");

        _tokenContract.transfer(_receiver, _balance);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory newBaseURI) public virtual onlyOwner {
        baseURI = newBaseURI;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
