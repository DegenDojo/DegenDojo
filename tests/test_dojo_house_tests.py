from scripts.helper import get_account, get_account2
from scripts.deploy import approve_erc20
from brownie import DojoHouse
import pytest
from web3 import Web3

LIQUIDITY_AMOUNT = Web3.toWei(30, "ether")


def test_enter_leave_house():
    account = get_account()
    dojo_house = DojoHouse[-1]
    # Test entering
    inital_lp = dojo_house.balanceOf(account)
    inital_balance = account.balance()
    tx = dojo_house.enter({"from": account, "value": LIQUIDITY_AMOUNT})
    tx.wait(1)
    # Check that we got the right amount of LP
    expected_lp_tokens = (
        dojo_house.totalSupply() / dojo_house.balance() * LIQUIDITY_AMOUNT
    )
    new_balance = dojo_house.balanceOf(account)
    assert new_balance == inital_lp + expected_lp_tokens
    # Check that we cannot leave for more that our balance
    with pytest.raises(Exception):
        dojo_house.leave(dojo_house.balanceOf(account) + 1000, {"from": account})
    # Check that we can leave with what we put in
    initial_house_bal = dojo_house.balance()
    tx = dojo_house.leave(dojo_house.balanceOf(account), {"from": account})
    tx.wait(1)
    # Check house funds were decreased
    assert dojo_house.balance() < initial_house_bal
    # Check we got money back - gas costs
    assert account.balance() >= inital_balance * 0.98
    # Check that we our DLP were burnt
    assert dojo_house.balanceOf(account) == 0
