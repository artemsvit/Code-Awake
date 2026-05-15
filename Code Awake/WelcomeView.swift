//
//  WelcomeView.swift
//  Code Awake
//
//  Created by Artem Svitelskyi on 15.05.2026.
//

import SwiftUI

struct WelcomeView: View {
    let onGetStarted: () -> Void
    @State private var isGetStartedHovered = false

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
            useCasesPanel
        }
        .frame(minWidth: 900, minHeight: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.07, green: 0.07, blue: 0.07))
        .ignoresSafeArea()
    }

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 24) {
                Image("WelcomeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 245)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Keep your Mac Awake.")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Code Awake lives quietly in the menu bar and keeps your work reachable when you need it.")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()
                .frame(height: 88)

            Button(action: onGetStarted) {
                Text("Get Started")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(red: 0.10, green: 0.09, blue: 0.10))
                    .frame(width: 174, height: 46)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 0.84, green: 0.49, blue: 0.92),
                                Color(red: 0.98, green: 0.78, blue: 0.58)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            }
            .buttonStyle(.plain)
            .scaleEffect(isGetStartedHovered ? 1.025 : 1.0)
            .shadow(
                color: Color(red: 0.84, green: 0.49, blue: 0.92).opacity(isGetStartedHovered ? 0.30 : 0.0),
                radius: isGetStartedHovered ? 18 : 0,
                x: 0,
                y: 10
            )
            .onHover { isHovering in
                isGetStartedHovered = isHovering

                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .animation(.easeOut(duration: 0.16), value: isGetStartedHovered)
        }
        .padding(.horizontal, 44)
        .padding(.vertical, 44)
        .frame(width: 430, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.08),
                    Color(red: 0.16, green: 0.11, blue: 0.15)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var useCasesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image("WelcomeUseCase")
                .resizable()
                .scaledToFill()
                .frame(width: 470, height: 300)
                .clipped()

            VStack(alignment: .leading, spacing: 14) {
                Text("Features")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                UseCaseRow(
                    icon: "cup.and.saucer.fill",
                    title: "Keep your Mac awake",
                    detail: "Prevent idle sleep while you work, build, download, or stay connected."
                )

                UseCaseRow(
                    icon: "macbook.and.iphone",
                    title: "Works with closed lid",
                    detail: "Best-effort support for phone and remote workflows when macOS allows closed-lid wake."
                )

                UseCaseRow(
                    icon: "restart.circle",
                    title: "Launch at Login",
                    detail: "Start Code Awake automatically and keep it ready in the menu bar."
                )
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)

            Spacer()
        }
        .frame(width: 470, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.10, green: 0.10, blue: 0.10))
    }
}

private struct UseCaseRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.65, blue: 0.56))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Text(detail)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
            }
        }
    }
}
