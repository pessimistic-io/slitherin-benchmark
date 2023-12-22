// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

// import "hardhat/console.sol";
import "./SafeMath.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./ERC721.sol";
import "./ReentrancyGuard.sol";

//  __       __              __
// /  \     /  |            /  |
// $$  \   /$$ |  ______   _$$ |_     ______
// $$$  \ /$$$ | /      \ / $$   |   /      \
// $$$$  /$$$$ |/$$$$$$  |$$$$$$/    $$$$$$  |
// $$ $$ $$/$$ |$$    $$ |  $$ | __  /    $$ |
// $$ |$$$/ $$ |$$$$$$$$/   $$ |/  |/$$$$$$$ |
// $$ | $/  $$ |$$       |  $$  $$/ $$    $$ |
// $$/      $$/  $$$$$$$/    $$$$/   $$$$$$$/
//
//  __       __                                               __
// /  \     /  |                                             /  |
// $$  \   /$$ |  ______    ______   ______   __    __   ____$$ |  ______    ______    _______
// $$$  \ /$$$ | /      \  /      \ /      \ /  |  /  | /    $$ | /      \  /      \  /       |
// $$$$  /$$$$ | $$$$$$  |/$$$$$$  |$$$$$$  |$$ |  $$ |/$$$$$$$ |/$$$$$$  |/$$$$$$  |/$$$$$$$/
// $$ $$ $$/$$ | /    $$ |$$ |  $$/ /    $$ |$$ |  $$ |$$ |  $$ |$$    $$ |$$ |  $$/ $$      \
// $$ |$$$/ $$ |/$$$$$$$ |$$ |     /$$$$$$$ |$$ \__$$ |$$ \__$$ |$$$$$$$$/ $$ |       $$$$$$  |
// $$ | $/  $$ |$$    $$ |$$ |     $$    $$ |$$    $$/ $$    $$ |$$       |$$ |      /     $$/
// $$/      $$/  $$$$$$$/ $$/       $$$$$$$/  $$$$$$/   $$$$$$$/  $$$$$$$/ $$/       $$$$$$$/

/// @title MetaMarauders
/// @author Smart-Chain Team

contract MetaMarauders is ERC721, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Strings for uint256;

    string public constant VERSION = "1";

    uint256 public mintableSupply;
    uint256 public priceSale = 0.1 ether;
    uint256 public allowMaxMint = 1;
    uint256 public allowMaxMint2 = 2;
    uint256 public allowMaxMint3 = 3;
    uint256 public constant maxMint = 25;
    uint256 public reservedSupplyAllocation;
    bool public saleIsActive;
    bool public saleAllowedIsActive;
    bool public saleHasEnded;
    address public reserveAddress;
    string public preRevealURI;
    string public proofSig;

    mapping(address => bool) _allowList;
    mapping(address => uint256) private _allowListClaimed;

    mapping(address => bool) _allowList2;
    mapping(address => uint256) private _allowListClaimed2;

    mapping(address => bool) _allowList3;
    mapping(address => uint256) private _allowListClaimed3;

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        string memory tokenBaseURI,
        uint256 mintableSupply_,
        uint256 reservedSupplyAllocation_,
        address reserveAddress_
    ) ERC721(tokenName, tokenSymbol) {
        require(
            mintableSupply_ > reservedSupplyAllocation_,
            "Cannot set reserve greater than supply"
        );
        mintableSupply = mintableSupply_;
        _setBaseURI(tokenBaseURI);
        saleIsActive = false;
        saleHasEnded = false;
        saleAllowedIsActive = false;
        reservedSupplyAllocation = reservedSupplyAllocation_;
        reserveAddress = reserveAddress_;
    }

    function addToAllowList(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "Cannot add zero address");

            _allowList[addresses[i]] = true;
            /**
             * @dev We don't want to reset _allowListClaimed count
             * if we try to add someone more than once.
             */
            _allowListClaimed[addresses[i]] > 0
                ? _allowListClaimed[addresses[i]]
                : 0;
        }
    }

    function onAllowList(address addr) external view returns (bool) {
        return _allowList[addr];
    }

    function removeFromAllowList(address[] calldata addresses)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(
                addresses[i] != address(0),
                "Cannot remove the zero address"
            );
            /// @dev We don't want to reset possible _allowListClaimed numbers.
            _allowList[addresses[i]] = false;
        }
    }

    function allowListClaimedBy(address owner_)
        external
        view
        returns (uint256)
    {
        require(owner_ != address(0), "Zero address not on Allow List");
        return _allowListClaimed[owner_];
    }

    function mintForAllowed(uint256 amountToMint)
        external
        payable
        nonReentrant
        returns (bool)
    {
        require(saleAllowedIsActive, "NFT sale is no longer available");
        require(amountToMint <= allowMaxMint, "Amount for minting is too high");
        require(_allowList[msg.sender], "You are not on the allowed list");
        uint256 supply = totalSupply();
        require(
            mintableSupply.sub(reservedSupplyAllocation) >=
                supply.add(amountToMint),
            "Mintable hardcap reached"
        );
        require(
            msg.value >= priceSale.mul(amountToMint),
            "Incorrect ETH amount sent"
        );
        require(
            _allowListClaimed[msg.sender] + amountToMint <= allowMaxMint,
            "Purchase exceeds max allowed"
        );
        for (uint256 i = 0; i < amountToMint; i++) {
            _allowListClaimed[msg.sender] += 1;
            _safeMint(msg.sender, supply.add(i));
        }
        return true;
    }

    ////////////////////

    function addToAllowList2(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "Cannot add zero address");

            _allowList2[addresses[i]] = true;
            /**
             * @dev We don't want to reset _allowListClaimed count
             * if we try to add someone more than once.
             */
            _allowListClaimed2[addresses[i]] > 0
                ? _allowListClaimed2[addresses[i]]
                : 0;
        }
    }

    function onAllowList2(address addr) external view returns (bool) {
        return _allowList2[addr];
    }

    function removeFromAllowList2(address[] calldata addresses)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(
                addresses[i] != address(0),
                "Cannot remove the zero address"
            );
            /// @dev We don't want to reset possible _allowListClaimed numbers.
            _allowList2[addresses[i]] = false;
        }
    }

    function allowListClaimedBy2(address owner_)
        external
        view
        returns (uint256)
    {
        require(owner_ != address(0), "Zero address not on Allow List 2");
        return _allowListClaimed2[owner_];
    }

    function mintForAllowed2(uint256 amountToMint)
        external
        payable
        nonReentrant
        returns (bool)
    {
        require(saleAllowedIsActive, "NFT sale is no longer available");
        require(
            amountToMint <= allowMaxMint2,
            "Amount for minting is too high"
        );
        require(_allowList2[msg.sender], "You are not on the allowed list");
        uint256 supply = totalSupply();
        require(
            mintableSupply.sub(reservedSupplyAllocation) >=
                supply.add(amountToMint),
            "Mintable hardcap reached"
        );
        require(
            msg.value >= priceSale.mul(amountToMint),
            "Incorrect ETH amount sent"
        );
        require(
            _allowListClaimed2[msg.sender] + amountToMint <= allowMaxMint2,
            "Purchase exceeds max allowed"
        );
        for (uint256 i = 0; i < amountToMint; i++) {
            _allowListClaimed2[msg.sender] += 1;
            _safeMint(msg.sender, supply.add(i));
        }
        return true;
    }

    //////////////////

    function addToAllowList3(address[] calldata addresses) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(addresses[i] != address(0), "Cannot add zero address");

            _allowList3[addresses[i]] = true;
            /**
             * @dev We don't want to reset _allowListClaimed count
             * if we try to add someone more than once.
             */
            _allowListClaimed3[addresses[i]] > 0
                ? _allowListClaimed3[addresses[i]]
                : 0;
        }
    }

    function onAllowList3(address addr) external view returns (bool) {
        return _allowList3[addr];
    }

    function removeFromAllowList3(address[] calldata addresses)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < addresses.length; i++) {
            require(
                addresses[i] != address(0),
                "Cannot remove the zero address"
            );
            /// @dev We don't want to reset possible _allowListClaimed numbers.
            _allowList3[addresses[i]] = false;
        }
    }

    function allowListClaimedBy3(address owner_)
        external
        view
        returns (uint256)
    {
        require(owner_ != address(0), "Zero address not on Allow List");
        return _allowListClaimed3[owner_];
    }

    function mintForAllowed3(uint256 amountToMint)
        external
        payable
        nonReentrant
        returns (bool)
    {
        require(saleAllowedIsActive, "NFT sale is no longer available");
        require(
            amountToMint <= allowMaxMint3,
            "Amount for minting is too high"
        );
        require(_allowList3[msg.sender], "You are not on the allowed list");
        uint256 supply = totalSupply();
        require(
            mintableSupply.sub(reservedSupplyAllocation) >=
                supply.add(amountToMint),
            "Mintable hardcap reached"
        );
        require(
            msg.value >= priceSale.mul(amountToMint),
            "Incorrect ETH amount sent"
        );
        require(
            _allowListClaimed3[msg.sender] + amountToMint <= allowMaxMint3,
            "Purchase exceeds max allowed"
        );
        for (uint256 i = 0; i < amountToMint; i++) {
            _allowListClaimed3[msg.sender] += 1;
            _safeMint(msg.sender, supply.add(i));
        }
        return true;
    }

    /////////////////////

    function mint(uint256 amountToMint)
        external
        payable
        nonReentrant
        returns (bool)
    {
        require(saleIsActive, "NFT sale is no longer available");
        require(amountToMint <= maxMint, "Amount for minting is too high");
        uint256 supply = totalSupply();
        require(
            mintableSupply.sub(reservedSupplyAllocation) >=
                supply.add(amountToMint),
            "Mintable hardcap reached"
        );
        require(
            msg.value >= priceSale.mul(amountToMint),
            "Incorrect ETH amount sent"
        );
        for (uint256 i = 0; i < amountToMint; i++) {
            _safeMint(msg.sender, supply.add(i));
        }
        return true;
    }

    function airdrop(address[] memory recipient)
        external
        onlyOwner
        returns (bool)
    {
        uint256 supply = totalSupply();
        require(
            recipient.length <= reservedSupplyAllocation,
            "Amount exceeds reserved allocation"
        );
        require(
            supply.add(recipient.length) <= mintableSupply,
            "Mintable hardcap reached"
        );
        for (uint256 i = 0; i < recipient.length; i++) {
            _safeMint(recipient[i], supply.add(i));
        }
        reservedSupplyAllocation = reservedSupplyAllocation.sub(
            recipient.length
        );
        return true;
    }

    function withdrawSale() external payable onlyOwner returns (bool) {
        require(
            payable(address(reserveAddress)).send(address(this).balance),
            "Error while withdrawing reserve"
        );
        return true;
    }

    function balanceOfUser(address userBalance)
        external
        view
        returns (uint256[] memory)
    {
        uint256 amountOfTokens = balanceOf(userBalance);
        uint256[] memory tokenIds = new uint256[](amountOfTokens);
        for (uint256 i = 0; i < amountOfTokens; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(userBalance, i);
        }
        return tokenIds;
    }

    function setSaleActiveStatus(bool saleActiveStatus_) external onlyOwner {
        saleIsActive = saleActiveStatus_;
    }

    function setSaleAllowedActiveStatus(bool saleActiveStatus_)
        external
        onlyOwner
    {
        saleAllowedIsActive = saleActiveStatus_;
    }

    function setSaleEndingStatus(bool saleEndingStatus_) external onlyOwner {
        saleHasEnded = saleEndingStatus_;
    }

    function setAllowMaxMint(uint256 allowMaxMint_) external onlyOwner {
        allowMaxMint = allowMaxMint_;
    }

    function setAllowMaxMint2(uint256 allowMaxMint_) external onlyOwner {
        allowMaxMint2 = allowMaxMint_;
    }

    function setAllowMaxMint3(uint256 allowMaxMint_) external onlyOwner {
        allowMaxMint3 = allowMaxMint_;
    }

    function setReservedSupplyAllocation(uint256 reservedSupplyAllocation_)
        external
        onlyOwner
    {
        reservedSupplyAllocation = reservedSupplyAllocation_;
    }

    function getPrice() external view returns (uint256) {
        return priceSale;
    }

    function setPrice(uint256 newPriceSale) external onlyOwner {
        priceSale = newPriceSale;
    }

    function setPreRevealURI(string memory preRevealURI_) external onlyOwner {
        preRevealURI = preRevealURI_;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _setBaseURI(baseURI);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        string memory base = baseURI();
        return
            saleHasEnded
                ? string(abi.encodePacked(base, tokenId.toString()))
                : preRevealURI;
    }

    function setProofSig(string calldata proofSig_) external onlyOwner {
        proofSig = proofSig_;
    }
}

