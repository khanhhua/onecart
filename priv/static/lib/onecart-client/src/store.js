import { createStore, applyMiddleware } from 'redux';
import thunk from 'redux-thunk';
import {VIEW_CART, VIEW_NONE, VIEW_SUMMARY, VIEW_ORDER, VIEW_THANK_YOU} from './consts';
import {
  ACTION_HIDE_CART,
  ACTION_INIT_CART,
  ACTION_UPDATE_CART,
  ACTION_SHOW_SUMMARY,
  ACTION_SHOW_CART,
  ACTION_REMOVE_ITEM,
  ACTION_CHECKOUT,
  ACTION_PLACE_ORDER
} from './consts';
import {STATUS_SUCCESS} from './consts';

function reducer(state = {items:[]}, action) {
  console.info('REDUCER:', action);
  let newState = Object.assign({}, state);

  if ('status' in action) {
    if (action.status !== STATUS_SUCCESS) {
      return state;
    }
  }

  switch (action.type) {
    case ACTION_SHOW_SUMMARY: {
      return {
        ...newState,
        view: VIEW_SUMMARY
      };
    }
    case ACTION_SHOW_CART: {
      return {
        ...newState,
        view: VIEW_CART
      };
    }
    case ACTION_HIDE_CART: {
      return {
        ...newState,
        view: VIEW_NONE
      };
    }
    case ACTION_INIT_CART: {
      const {payload: {appid, items}} = action;
      return {
        ...newState,
        appid,
        items,
      };
    }
    case ACTION_UPDATE_CART: {
      const {payload: {items}} = action;
      return {
        ...newState,
        items
      };
    }
    case ACTION_REMOVE_ITEM: {
      const {payload: {items}} = action;
      return {
        ...newState,
        items
      };
    }
    case ACTION_CHECKOUT: {
      const {payload: order} = action;
      return {
        ...newState,
        view: VIEW_ORDER,
        order,
        items: [],
      };
    }
    case ACTION_PLACE_ORDER: {
      const {payload: {order}} = action;
      return {
        ...newState,
        view: VIEW_THANK_YOU,
        order,
      };
    }
  }

  return newState;
}

export default function (initialState = {items:[]}) {
  return createStore(reducer, initialState, applyMiddleware(thunk));
}