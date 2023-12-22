// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Pausable.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";
import "./SpaceNerd.sol";

contract SpaceBuffer is Ownable, Pausable, ReentrancyGuard {
    event Received(address, uint256);

    //owner events
    event SetAllowContract(bool);
    event SetRound(ROUND);
    event SetTreasuryAddress(address);
    event SetSpace(address);
    event SetMaxMintable(uint256);
    event SetMintPrice(uint256);

    //mint event
    event BuySpaces(address, uint256);

    enum ROUND {
        None,
        Owner,
        Sale
    }

    /////////////////////
    // Public Variables
    /////////////////////

    uint256 public constant MAX_SUPPLY = 1000; // MAX_SUPPLY = 1402 - 402(burned)  = 1000
    uint256 public constant Max_Owner_Mint = 45;
    uint256 private maxMintable = 100;
    uint256 tokenIdCounter = 650; //605(minted) + 45(collab reserve)
    uint256 public mintPrice = 0.1 ether;
    ROUND public round = ROUND.None;
    address public treasuryAddress;
    bool private allowContract;

    SpaceNerd private space;

    constructor(address _treasury, address payable _space) {
        treasuryAddress = _treasury;
        space = SpaceNerd(_space);
    }

    //////////////////////
    // Setters for Owner
    //////////////////////

    function setTreasuryAddress(address addr) public onlyOwner {
        require(addr != address(0), "address 0");
        treasuryAddress = addr;
        emit SetTreasuryAddress(addr);
    }

    function setRound(ROUND round_) public onlyOwner {
        round = round_;
        emit SetRound(round_);
    }

    function setSpace(address _space) public onlyOwner {
        space = SpaceNerd(payable(_space));
        emit SetSpace(_space);
    }

    function setAllowContract(bool _allow) public onlyOwner {
        allowContract = _allow;
        emit SetAllowContract(_allow);
    }

    function setMaxMintable(uint256 _max) public onlyOwner {
        maxMintable = _max;
        emit SetMaxMintable(_max);
    }

    function setMintPrice(uint256 _price) public onlyOwner {
        mintPrice = _price;
        emit SetMintPrice(_price);
    }

    ////////////
    // minting
    ////////////

    function buySpaces(address _to, uint256 quantity)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        //payment
        uint256 cost = 0;
        cost = quantity * mintPrice;

        // conditions
        require(round != ROUND.None, "Mint has not started");
        if (round == ROUND.Owner) {
            require(msg.sender == owner(), "only owner mint");
            for (uint256 i = 0; i < Max_Owner_Mint; i++) {
                space.transferFrom(address(this), _to, 605 + i);
            }
            emit BuySpaces(_to, Max_Owner_Mint);
        } else {
            requestMint();
            require(msg.value == cost, "Unmatched ether balance");
            require(quantity <= maxMintable, "exceed maxMintable");
            require(
                treasuryAddress != address(0),
                "treasury wallet is not set"
            );

            for (uint256 i = 0; i < quantity; i++) {
                space.transferFrom(
                    address(this),
                    msg.sender,
                    tokenIdCounter + i
                );
            }
            tokenIdCounter += quantity;

            require(tokenIdCounter <= MAX_SUPPLY, "mint amount exceeds supply");
            emit BuySpaces(msg.sender, quantity);
        }
    }

    //////////////
    // owner functions
    //////////////

    // Withdraw ETH
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(treasuryAddress != address(0), "transfer to address 0");
        payable(treasuryAddress).transfer(balance);
    }

    // Pausable
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // owner transfer Spaces in batch
    function transferFromSpaceBatch(
        address[] calldata tos,
        uint256[] calldata _tokenIds
    ) external onlyOwner nonReentrant whenNotPaused {
        require(tos.length == _tokenIds.length, "length not match");
        for (uint256 i = 0; i < tos.length; i++) {
            require(_tokenIds[i] <= 999, "token was burned");
            space.transferFrom(address(this), tos[i], _tokenIds[i]);
        }
    }

    //owner transfer single space
    function transferFromSpace(address to, uint256 id) public onlyOwner {
        require(id <= 999, "token was burned");
        space.transferFrom(address(this), to, id);
    }

    /////////////////
    // utils
    /////////////////
    // function supportsInterface(bytes4 interfaceId)
    //     public
    //     view
    //     virtual
    //     override(
    //         ERC721A /*, IERC165*/
    //     )
    //     returns (bool)
    // {
    //     return super.supportsInterface(interfaceId);
    // }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function requestMint() private view {
        if (!allowContract) {
            require(
                tx.origin == msg.sender,
                "only EOA can mint, not a contract"
            );
        }
    }

    /////////////
    // Fallback
    /////////////

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    fallback() external payable {
        revert();
    }
}

