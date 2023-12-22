// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.17;

//---------------------------------------------------------
// Imports
//---------------------------------------------------------
import "./ERC1155.sol";
import "./Ownable.sol";

//---------------------------------------------------------
// Contract
//---------------------------------------------------------
contract XNFTBase is ERC1155
{
	uint256 total_minted_amount;

	address public address_operator;	
	mapping(address => bool) public is_controller;

	mapping(uint256 => uint256) public minted_amount_list; // grade / mint amount

	// URI Format
	// ipfs://bafybeidajqcl52q4jlk7dz3wzfj4f665x6mzdjer5abzeh4ib7p6dz6cme
	// https://ipfs.io/ipfs/CID/{id}.json
	// https://dweb.link/ipfs/bafybeidajqcl52q4jlk7dz3wzfj4f665x6mzdjer5abzeh4ib7p6dz6cme/{id}.json
	// https://bafkreigdgroagua3ti2yfmzbntdf6r6fmeirb2qrcsbn5ek2di6mqpmb6a.ipfs.dweb.link/
	string internal uri_base_str = "https://dweb.link/ipfs/";
	string internal uri_param_str = "/{id}.json";
	string internal cid_str;

	string[] internal metadata_list;
	// OpenSea MetaData Format
	// {
	//   "description": "Friendly OpenSea Creature that enjoys long swims in the ocean.",
	//   "external_url": "https://openseacreatures.io/3",
	//   "image": "https://storage.googleapis.com/opensea-prod.appspot.com/puffs/3.png",
	//   "name": "Dave Starbelly",
	//   "attributes": [ ... ]
	// }

	//---------------------------------------------------------------
	// Front-end connectors
	//---------------------------------------------------------------
	event SetOperatorCB(address indexed operator, address _new_address);
	event SetControllerCB(address indexed operator, address _new_address);

	//---------------------------------------------------------------
	// Modifier
	//---------------------------------------------------------------
	modifier onlyOperator() { require(address_operator == msg.sender, "onlyOperator: caller is not the operator");	_; }
	modifier onlyController() { require(is_controller[msg.sender] == true, "onlyController: caller is not the controller"); _; }

	//---------------------------------------------------------------
	// External Method
	//---------------------------------------------------------------
	constructor(string memory CID) ERC1155(string.concat(string.concat(uri_base_str, CID), uri_param_str))
	{
		address_operator = msg.sender;
		cid_str = CID;
	}

	function mint(address _to, uint256 _grade) external onlyController
	{
		require(_grade > 0 && _grade < 10, "mint: wrong grade");
		require(minted_amount_list[_grade] < 1e6, "mint: total mint limit exceed");

		uint256 nft_id = get_nft_id(_grade, minted_amount_list[_grade]);

		_mint(_to, nft_id, 1, "");

		minted_amount_list[_grade] += 1;
	}

	function burn(uint256 _id, uint256 _amount) external onlyOperator
	{
		_burn(msg.sender, _id, _amount);
	}

	function get_grade(uint256 _id) public pure returns(uint256)
	{
		return _id / 1e6;
	}

	function get_nft_id(uint256 _grade, uint256 _serial) public pure returns(uint256)
	{
		return _grade * 1e6 + _serial;
	}
		
	function uri(uint256 _id) public view virtual override returns(string memory)
	{
		string memory grade_str = uint2str(get_grade(_id));

		string memory instance_uri = uri_base_str;
		instance_uri = string.concat(instance_uri, cid_str);
		instance_uri = string.concat(instance_uri, "/");
		instance_uri = string.concat(instance_uri, grade_str);
		instance_uri = string.concat(instance_uri, ".json");
		
		return instance_uri;
	}

	// legacy
	function get_list(uint256 /*count*/) public view returns(uint256[] memory) 
	{
		return get_my_id_list();
	}

	function get_my_id_list() public view returns(uint256[] memory) 
	{
		uint256 cur_len=0;
		uint256[] memory id_list;

		for(uint256 grade=0; grade < 10; grade++)
		{
			uint256 minted_amount = minted_amount_list[grade];
			if(minted_amount == 0)
				continue;
			
			for(uint256 i=minted_amount; i > 0; i--)
			{
				uint256 nft_id = get_nft_id(grade, i-1);
				if(balanceOf(msg.sender, nft_id) > 0)
					cur_len++;
			}
		}

		id_list = new uint256[](cur_len);
		cur_len = 0;
		for(uint256 grade = 0; grade < 10; grade++)
		{
			uint256 minted_amount = minted_amount_list[grade];
			if(minted_amount == 0)
				continue;
			
			for(uint256 i = minted_amount; i > 0; i--)
			{
				uint256 nft_id = get_nft_id(grade, i - 1);
				if(balanceOf(msg.sender, nft_id) > 0) 
				{
					id_list[cur_len] = nft_id;
					cur_len++;
				}
			}
		}

		return id_list;
	}

	//---------------------------------------------------------------
	// Setters
	//---------------------------------------------------------------
	function set_operator(address _new_address) public onlyOperator
	{
		require(_new_address != address(0), "set_operator: Wrong address");

		address_operator = _new_address;
		emit SetOperatorCB(msg.sender, _new_address);
	}

	function set_controller(address _new_address, bool _is_set) public onlyOperator
	{
		require(_new_address != address(0), "set_controller: Wrong address");

		is_controller[_new_address] = _is_set;
		emit SetControllerCB(msg.sender, _new_address);
	}

	function uint2str(uint256 _i) internal pure returns(string memory str)
	{
		if(_i == 0)
			return "0";
		
		uint256 j = _i;
		uint256 length;
		while(j != 0)
		{
			length++;
			j /= 10;
		}
		
		bytes memory bstr = new bytes(length);
		uint256 k = length;
		j = _i;
		
		while(j != 0)
		{
			bstr[--k] = bytes1(uint8(48 + j % 10));
			j /= 10;
		}

		str = string(bstr);
	}
}

