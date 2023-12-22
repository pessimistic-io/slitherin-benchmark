// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;
import "./ERC1155.sol";
import "./Ownable.sol";

contract Minter is ERC1155, Ownable {
    struct dropInfo {
        address creator;
        uint256 supply;
        uint256 maxSupply;
        uint256 price;
        bool active;
        string uri;
    }
    uint256 id;
    mapping(uint256 => dropInfo) public drops;
    mapping(address => uint256[]) internal createdDrops;
    mapping(address => uint256) public userBalance;

    constructor() ERC1155("") {}

    modifier onlyCreator(uint256 _id) {
        require(drops[_id].creator == msg.sender, "Only creator can do this");
        _;
    }

    function uri(uint256 _id) public view override returns (string memory) {
        return drops[_id].uri;
    }

    function createDrop(
        uint256 _maxSupply,
        uint256 _price,
        string memory _uri
    ) external {
        createdDrops[msg.sender].push(id);
        drops[id] = dropInfo(msg.sender, 0, _maxSupply, _price, true, _uri);
        id++;
    }

    function editDrop(
        uint256 _id,
        uint256 _maxSupply,
        uint256 _price,
        string memory _uri
    ) external onlyCreator(_id) {
        require(_maxSupply > drops[_id].supply, "Max supply too low");
        drops[_id].maxSupply = _maxSupply;
        drops[_id].price = _price;
        drops[_id].uri = _uri;
    }

    function creatorMint(
        uint256 _id,
        uint256[] calldata _amounts,
        address[] calldata recipeints
    ) external onlyCreator(_id) {
        require(
            _amounts.length == recipeints.length,
            "Amount and recipeints must be same length"
        );
        for (uint256 i = 0; i < _amounts.length; i++) {
            require(
                drops[_id].supply + _amounts[i] <= drops[_id].maxSupply,
                "Max supply reached"
            );
            drops[_id].supply += _amounts[i];
            _mint(recipeints[i], _id, _amounts[i], "");
        }
    }

    function flipStatus(uint256 _id) external onlyCreator(_id) {
        drops[_id].active
            ? drops[_id].active = false
            : drops[_id].active = true;
    }

    function publicMint(uint256 _id, uint256 _amount) external payable {
        require(drops[_id].active, "Drop not active");
        require(
            drops[_id].supply + _amount <= drops[_id].maxSupply,
            "Max supply reached"
        );
        require(
            msg.value == drops[_id].price * _amount,
            "Incorrect amount sent"
        );
        drops[_id].supply += _amount;
        userBalance[msg.sender] += msg.value;
        _mint(msg.sender, _id, _amount, "");
    }

    function withdraw() external {
        uint256 amount = userBalance[msg.sender];
        userBalance[msg.sender] = 0;
        payable(msg.sender).transfer(amount);
    }

    function getCreatedDrops(address _creator)
        external
        view
        returns (uint256[] memory)
    {
        return createdDrops[_creator];
    }
}

