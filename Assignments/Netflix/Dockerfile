FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /app
COPY Netflix/Netflix.csproj Netflix/
RUN dotnet restore Netflix/
COPY Netflix .
RUN dotnet publish . \
      --configuration Release --output /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 as final
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 5000
ENV ASPNETCORE_URLS=5000
ENTRYPOINT ["dotnet", "Netflix.dll"]
