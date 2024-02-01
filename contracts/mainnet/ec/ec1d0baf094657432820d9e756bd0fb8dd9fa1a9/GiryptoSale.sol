// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./ECDSA.sol";
import "./ReentrancyGuard.sol";
import "./IERC721.sol";
import "./Pausable.sol";



interface IG_ERC721A is IERC721 {
    function massMint(address to, uint256 amount) external;
    function totalSupply() external returns (uint256);
}

interface IF_ERC721A is IERC721 {
    function addLevel(uint256 tokenId) external;

    function tokenOfOwnerByIndex(address owner, uint256 index)
        external
        view
        returns (uint256);

    function fablesLevel(uint256 tokenId) external view returns (uint256);
}

contract GiryptoSale is Ownable, ReentrancyGuard, Pausable {
    uint256 public price = 0.126 ether;
    uint256 public sellAmount = 0;
    uint256 public constant maxSell = 3000;

    IF_ERC721A public f_ERC721;
    IG_ERC721A public g_ERC721;

    address public communityWallet;

    uint256 public saleStartTime;
    uint256 public saleEndTime;

    event LevelUp(address indexed from, uint256[] tokenIds,uint256 currentSupply);

    constructor(
        address _f,
        address _g,
        address _wallet,
        uint256 _price,
        uint256 start,
        uint256 end
    ) {
        price = _price;
        f_ERC721 = IF_ERC721A(_f);
        g_ERC721 = IG_ERC721A(_g);
        communityWallet = _wallet;

        saleStartTime = start;
        saleEndTime = end;
    }

    /*
    GET
    */
    function CheckClearTokens(address from)
        external
        view
        returns (uint256[] memory)
    {
        uint256 bal = f_ERC721.balanceOf(from);

        uint256[] memory balTokens = new uint256[](bal);
        uint256 count = 0;
        for (uint256 i = 0; i < bal; i++) {
            uint256 tokenId = f_ERC721.tokenOfOwnerByIndex(from, i);

            if (f_ERC721.fablesLevel(tokenId) == 0) {
                balTokens[count] = tokenId;
                count++;
            }
        }

        uint256[] memory clearTokens = new uint256[](count);
        for(uint256 i=0 ; i< count;i++){
            clearTokens[i] = balTokens[i];
        }

        return clearTokens;
    }


    /*
    SET onlyOwner
    */
    function setSaleTime(
        uint256 _start,
        uint256 _end
    ) external onlyOwner {
        saleStartTime = _start;
        saleEndTime = _end;
    }

    function setPrice(uint256 _price) external onlyOwner {
        price = _price;
    }

    function setPause(bool _p) external onlyOwner {
        if (_p) {
            _pause();
        } else {
            _unpause();
        }
    }

    /*
    Only communityWallet
    */
    function Withdraw_Eth() public {
        require(msg.sender == communityWallet, "Not Authorized");
        uint256 eth_Balance = address(this).balance;
        (bool isSuccess, ) = payable(communityWallet).call{value: eth_Balance}(
            ""
        );
        require(isSuccess, "Failed To Withdraw Eth");
    }

    /*
    Payable
    */
    function PayForMint(bytes memory _signature, uint256[] memory _tokenIds)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        address sender = msg.sender;

        uint256 amount = _tokenIds.length;
        uint256 totalPrice = price * amount;

        uint256 currentSupply = g_ERC721.totalSupply();

        require(!_isContract(sender), "Invalid Sender");
        require(_verifySigner(_signature, sender), "Invalid Signer");
        require(msg.value == totalPrice, "Not Enough Eth");
        require(sellAmount + amount <= maxSell, "Max Supply");
        require(f_ERC721.balanceOf(sender) > 0, "Invalid F balance");

        for (uint256 i = 0; i < amount; i++) {
            require(f_ERC721.ownerOf(_tokenIds[i]) == sender, "Invalid Owner");
            require(f_ERC721.fablesLevel(_tokenIds[i]) == 0, "Already LevelUp");
        }

        require (
            block.timestamp >= saleStartTime &&
            block.timestamp < saleEndTime,
            "Mint not start yet"
        );

        g_ERC721.massMint(sender, amount);
        _levelUp(sender, _tokenIds,currentSupply);

        sellAmount += amount;
    }

    /*
    Internal
    */
    function _levelUp(address sender, uint256[] memory tokenIds , uint256 currentSupply) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            f_ERC721.addLevel(tokenIds[i]);
        }
        emit LevelUp(sender, tokenIds,currentSupply);
    }

    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function _verifySigner(bytes memory _signature, address _to)
        internal
        pure 
        returns (bool)
    {
        bytes32 hash = keccak256(abi.encode(_to));
        bytes32 ECDSA_Hash = ECDSA.toEthSignedMessageHash(hash);

        return (ECDSA.recover(ECDSA_Hash, _signature) == _to);
    }
}

