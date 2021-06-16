//
//  AutoCompleteViewModel.swift
//  Mastodon
//
//  Created by MainasuK Cirno on 2021-5-17.
//

import UIKit
import Combine
import GameplayKit
import MastodonSDK

final class AutoCompleteViewModel {
    
    var disposeBag = Set<AnyCancellable>()
    
    // input
    let context: AppContext
    let inputText = CurrentValueSubject<String, Never>("")  // contains "@" or "#" prefix
    let symbolBoundingRect = CurrentValueSubject<CGRect, Never>(.zero)
    let customEmojiViewModel = CurrentValueSubject<EmojiService.CustomEmojiViewModel?, Never>(nil)
    
    // output
    var autoCompleteItems = CurrentValueSubject<[AutoCompleteItem], Never>([])
    var diffableDataSource: UITableViewDiffableDataSource<AutoCompleteSection, AutoCompleteItem>!
    private(set) lazy var stateMachine: GKStateMachine = {
        // exclude timeline middle fetcher state
        let stateMachine = GKStateMachine(states: [
            State.Initial(viewModel: self),
            State.Loading(viewModel: self),
            State.Fail(viewModel: self),
            State.Idle(viewModel: self),
        ])
        stateMachine.enter(State.Initial.self)
        return stateMachine
    }()
    
    init(context: AppContext) {
        self.context = context
        
        autoCompleteItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                guard let diffableDataSource = self.diffableDataSource else { return }

                var snapshot = NSDiffableDataSourceSnapshot<AutoCompleteSection, AutoCompleteItem>()
                snapshot.appendSections([.main])
                snapshot.appendItems(items, toSection: .main)
                if let currentState = self.stateMachine.currentState {
                    switch currentState {
                    case is State.Loading, is State.Fail:
                        if items.isEmpty {
                            snapshot.appendItems([.bottomLoader], toSection: .main)
                        }
                    case is State.Idle:
                        // TODO: handle no results
                        break
                    default:
                        break
                    }
                }
                
                diffableDataSource.defaultRowAnimation = .fade
                diffableDataSource.apply(snapshot)
            }
            .store(in: &disposeBag)
        
        inputText
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] inputText in
                guard let self = self else { return }
                self.stateMachine.enter(State.Loading.self)
            }
            .store(in: &disposeBag)
    }
    
}

extension AutoCompleteViewModel {
    enum SearchType {
        case accounts
        case hashtags
        case emoji
        case `default`

        public var mastodonSearchType: Mastodon.API.V2.Search.SearchType? {
            switch self {
            case .accounts:     return .accounts
            case .hashtags:     return .hashtags
            case .emoji:        return nil
            case .default:      return .default
            }
        }
        
        init?(inputText: String) {
            let prefix = inputText.first ?? Character("_")
            switch prefix {
            case "@":   self = .accounts
            case "#":   self = .hashtags
            case ":":   self = .emoji
            default:    return nil
            }
        }
    }
}