//why sdk runtime because it containes tools for build and publish
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY . .
RUN dotnet publish . \
    --configuration Release --output /src/publish


FROM mcr.microsoft.com/dotnet/aspnet:10.0 as final
WORKDIR /app
COPY --from=build /app/publish .
ENV ASPNETCORE_URLS=5000
EXPOSE 5000
ENTRYPOINT ["dotnet", "Netflix.dll"]