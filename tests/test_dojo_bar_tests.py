from scripts.helper import get_account, get_account2
from scripts.deploy import approve_erc20
from brownie import DegenDojo, DojoBar, DojoHouse
import pytest
import time
from web3 import Web3

ENTER_AMOUNT = Web3.toWei(10 ** 4, "ether")
LIQUIDITY_AMOUNT = Web3.toWei(30, "ether")
LARGE_TRADE = Web3.toWei(0.7, "ether")
SMALL_TRADE = Web3.toWei(0.2, "ether")


def test_enter_leave():
    account = get_account()
    dojo_bar = DojoBar[-1]
    dojo_token = DegenDojo[-1]
    # test a regular entrance
    # - approve erc20
    tx1 = approve_erc20(ENTER_AMOUNT * 2, dojo_bar, dojo_token, account)
    tx1.wait(1)
    # check initial bar amount
    inital_bar_count = dojo_token.balanceOf(dojo_bar)
    inital_xDojo = dojo_bar.balanceOf(account)
    tx2 = dojo_bar.enter(ENTER_AMOUNT, {"from": account})
    tx2.wait(1)
    # check the bar has gotten an increase in dojo
    assert dojo_token.balanceOf(dojo_bar) == inital_bar_count + ENTER_AMOUNT
    # check account has been minted xDOJO
    assert dojo_bar.balanceOf(account) > inital_xDojo
    # try enter with more than our account
    with pytest.raises(Exception):
        dojo_bar.enter(dojo_token.balanceOf(account) + 1000, {"from": account})
    # test leaving
    xDOJO_leave_amount = dojo_bar.balanceOf(account)
    DOJO_bal = dojo_token.balanceOf(account)
    xDOJO_supply = dojo_bar.totalSupply()
    # - check cant leave with more than we want
    with pytest.raises(Exception):
        dojo_bar.leave(xDOJO_leave_amount + 1000, {"from": account})
    # test leaving
    tx = dojo_bar.leave(xDOJO_leave_amount, {"from": account})
    tx.wait(1)
    # try leaving again
    with pytest.raises(Exception):
        dojo_bar.leave(xDOJO_leave_amount, {"from": account})
    # check the dojo was given back
    assert dojo_token.balanceOf(account) > DOJO_bal
    # check the xdojo was burnt
    assert dojo_bar.totalSupply() == xDOJO_supply - xDOJO_leave_amount
    # check that the dojo ratio was unaffected


def test_get_ratio():
    account = get_account()
    dojo_bar = DojoBar[-1]
    dojo_token = DegenDojo[-1]
    tx1 = approve_erc20(ENTER_AMOUNT * 2, dojo_bar, dojo_token, account)
    tx1.wait(1)
    # make sure ratio is not 0
    tx2 = dojo_bar.enter(ENTER_AMOUNT, {"from": account})
    tx2.wait(1)
    # check ratio is what is expected
    bar_balance = dojo_token.balanceOf(dojo_bar)
    xdojo_supply = dojo_bar.totalSupply()
    expected_ratio = bar_balance / xdojo_supply
    assert dojo_bar.getRatio() == expected_ratio
    # make sure entering and exiting doenst change ratio
    tx3 = dojo_bar.enter(ENTER_AMOUNT, {"from": account})
    tx3.wait(1)
    assert dojo_bar.getRatio() == expected_ratio
    xDOJO_leave_amount = dojo_bar.balanceOf(account) - 1000
    tx4 = dojo_bar.leave(xDOJO_leave_amount, {"from": account})
    tx4.wait(1)
    assert dojo_bar.getRatio() == expected_ratio


def test_collect_fees():
    account = get_account()
    dojo_bar = DojoBar[-1]
    dojo_token = DegenDojo[-1]
    dojo_house = DojoHouse[-1]
    # first make sure theres no tokens to claim
    inital_ratio = dojo_bar.getRatio()
    initial_dojo_bal = dojo_token.balanceOf(dojo_bar)
    # see if liqudity needed
    if dojo_house.balance() < LIQUIDITY_AMOUNT:
        tx = dojo_house.enter({"from": account, "value": LIQUIDITY_AMOUNT})
        tx.wait(1)
    dojo_token.initiateTrade(1, {"from": account, "value": LARGE_TRADE})
    time.sleep(180)
    tx = dojo_token.claimTrade({"from": account})
    tx.wait(1)
    remainder = dojo_house.balanceOf(account)
    dojo_house.leave(remainder, {"from": account})
    # check the hosue has gotten fees
    assert dojo_bar.balance() != 0
    tx = dojo_bar.collectFees({"from": account})
    # check the bar balance was all spent
    assert dojo_bar.balance() == 0
    # check the amount of dojo increased
    assert dojo_token.balanceOf(dojo_bar) > initial_dojo_bal
    # check that the ratio increased
    assert dojo_bar.getRatio() > inital_ratio
